---@module "aru.nav.point_jump"
---@brief Buffer-local semantic jump history.
---
--- A point belongs to a Treesitter-backed editing area when possible. Small
--- semantic nodes own one point; large nodes may own several bounded local
--- areas. Each entry has a fixed area anchor and a mutable return target, so
--- revisiting an area updates its landing position without allowing the area
--- itself to drift through the buffer.

local buf = require("aru.buf")
local quick_close = require("aru.quick_close")
local ts = require("aru.ts")

local M = {}

---@class AruPointJump.Config
---@field debounce_ms number
---@field max_history number
---@field min_block_lines number
---@field max_semantic_area_lines number
---@field locality_lines number
---@field max_ts_field_len number
---@field capture_priority table<string, number>
---@field exclude_filetypes string[]
---@field augroup_id number?
---@field namespace number
local default_config = {
    debounce_ms = 250,
    max_history = 10,
    min_block_lines = 12,
    max_semantic_area_lines = 30,
    locality_lines = 20,
    max_ts_field_len = 32,
    capture_priority = {
        ["block.outer"] = 1,
        ["function.outer"] = 2,
        ["method.outer"] = 2,
        ["class.outer"] = 3,
    },
    -- Feature-specific additions beyond aru.buf's shared plugin UI set.
    exclude_filetypes = {},
    augroup_id = nil,
    namespace = vim.api.nvim_create_namespace("aru_point_jump"),
}

---@type AruPointJump.Config
M.config = vim.deepcopy(default_config)

---@class AruPointJump.View : vim.fn.winrestview.dict
---@field lnum number
---@field col number
---@field botline number

---@class AruPointJump.SemanticArea
---@field capture string
---@field kind string
---@field name string?
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number

---@class AruPointJump.Entry
---@field anchor_view AruPointJump.View
---@field target_view AruPointJump.View
---@field semantic AruPointJump.SemanticArea

---@class AruPointJump.History
---@field index number
---@field entries AruPointJump.Entry[]

---@class AruPointJump.EntryExtmarks
---@field anchor number
---@field target number

---@class AruPointJump.CursorPosition
---@field lnum number
---@field col number

---@class AruPointJump.Session
---@field bufnr number
---@field changetick number
---@field debounce uv.uv_timer_t
---@field extmarks table<AruPointJump.Entry, AruPointJump.EntryExtmarks>
---@field ignore_cursor AruPointJump.CursorPosition?

---@class AruPointJump.BufferState
---@field history AruPointJump.History
---@field session AruPointJump.Session?

---@type table<string, AruPointJump.BufferState>
M.buffers = {}

---@param view AruPointJump.View
---@return AruPointJump.View
local function copy_view(view) return vim.tbl_extend("force", {}, view) end

---@return AruPointJump.View
local function capture_view()
    return vim.tbl_extend("force", {}, vim.fn.winsaveview(), { botline = vim.fn.line("w$") })
end

---@param bufnr number
---@return string?
local function trackable_path(bufnr)
    if not buf.is_loaded(bufnr) then return nil end

    local path = buf.normal_file_path(bufnr)
    if not path then return nil end

    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if vim.tbl_contains(M.config.exclude_filetypes, filetype) then return nil end
    if quick_close.is_quick_close_buffer(bufnr) then return nil end

    return path
end

---@param semantic AruPointJump.SemanticArea
---@param row number
---@param col number
---@return boolean
local function semantic_contains(semantic, row, col)
    if row < semantic.start_row or row > semantic.end_row then return false end
    if row == semantic.start_row and col < semantic.start_col then return false end

    -- Treesitter ranges are end-exclusive.
    if row == semantic.end_row and col >= semantic.end_col then return false end

    return true
end

---@param semantic AruPointJump.SemanticArea
---@return number
local function semantic_line_count(semantic)
    local count = semantic.end_row - semantic.start_row
    if semantic.end_col > 0 then count = count + 1 end
    return math.max(count, 1)
end

---@param bufnr number
---@param view AruPointJump.View
---@return AruPointJump.SemanticArea?
local function semantic_area_at(bufnr, view)
    local iterator = ts.iter_textobj_captures(bufnr)
    if not iterator then return nil end

    local row = view.lnum - 1
    local col = view.col
    local best = nil

    for id, node in iterator.iter do
        local capture = iterator.query.captures[id]
        local weight = M.config.capture_priority[capture]
        if not weight then goto continue end

        local sr, sc, er, ec = node:range()
        local semantic = {
            capture = capture,
            kind = node:type(),
            name = ts.node_field_text(node, "name", bufnr, M.config.max_ts_field_len),
            start_row = sr,
            start_col = sc,
            end_row = er,
            end_col = ec,
        }
        local lines = semantic_line_count(semantic)

        if capture == "block.outer" and lines < M.config.min_block_lines then goto continue end
        if not semantic_contains(semantic, row, col) then goto continue end

        if not best or weight < best.weight or (weight == best.weight and lines < best.lines) then
            best = { area = semantic, weight = weight, lines = lines }
        end

        ::continue::
    end

    return best and best.area or nil
end

---@param area AruPointJump.SemanticArea
---@param other AruPointJump.SemanticArea
---@return boolean
local function same_semantic_area(area, other)
    -- Entry semantics are reclassified from their extmark before matching, so
    -- both sides refer to the current parse. Exact ranges avoid conflating
    -- adjacent blocks or duplicate symbol names.
    return area.capture == other.capture
        and area.kind == other.kind
        and area.name == other.name
        and area.start_row == other.start_row
        and area.start_col == other.start_col
        and area.end_row == other.end_row
        and area.end_col == other.end_col
end

---@param entry AruPointJump.Entry
---@param semantic AruPointJump.SemanticArea
---@param view AruPointJump.View
---@return boolean
local function entry_matches(entry, semantic, view)
    if not same_semantic_area(entry.semantic, semantic) then return false end
    if semantic_line_count(semantic) <= M.config.max_semantic_area_lines then return true end
    return math.abs(entry.anchor_view.lnum - view.lnum) <= M.config.locality_lines
end

---@param session AruPointJump.Session
---@param view AruPointJump.View
---@param extmark_id number?
---@return number
local function set_extmark(session, view, extmark_id)
    local line_count = vim.api.nvim_buf_line_count(session.bufnr)
    local row = math.min(view.lnum - 1, line_count - 1)
    local line = vim.api.nvim_buf_get_lines(session.bufnr, row, row + 1, false)[1]
    local col = math.min(view.col, #line)
    return vim.api.nvim_buf_set_extmark(session.bufnr, M.config.namespace, row, col, {
        id = extmark_id,
        right_gravity = true,
        end_row = row,
        end_col = math.min(col + 1, #line),
        end_right_gravity = true,
    })
end

---@param session AruPointJump.Session
---@param entry AruPointJump.Entry
local function delete_entry_extmarks(session, entry)
    local extmarks = session.extmarks[entry]
    vim.api.nvim_buf_del_extmark(session.bufnr, M.config.namespace, extmarks.anchor)
    vim.api.nvim_buf_del_extmark(session.bufnr, M.config.namespace, extmarks.target)
    session.extmarks[entry] = nil
end

---@param session AruPointJump.Session
---@param extmark_id number
---@param view AruPointJump.View
local function refresh_view_from_extmark(session, extmark_id, view)
    local pos =
        vim.api.nvim_buf_get_extmark_by_id(session.bufnr, M.config.namespace, extmark_id, {})
    local old_lnum = view.lnum
    view.lnum = pos[1] + 1
    view.col = pos[2]

    -- Keep the saved viewport moving with the cursor anchor when edits happen
    -- above it. Extmarks track the cursor itself, not winsaveview()'s topline.
    local delta = view.lnum - old_lnum
    view.topline = math.max(1, view.topline + delta)
    view.botline = math.max(1, view.botline + delta)
end

---@param state AruPointJump.BufferState
---@param session AruPointJump.Session
local function sanitize_history(state, session)
    for index = #state.history.entries, 1, -1 do
        local entry = state.history.entries[index]
        local extmarks = session.extmarks[entry]
        refresh_view_from_extmark(session, extmarks.anchor, entry.anchor_view)
        refresh_view_from_extmark(session, extmarks.target, entry.target_view)

        local semantic = semantic_area_at(session.bufnr, entry.anchor_view)
        if semantic then
            entry.semantic = semantic
        else
            -- Point history contains semantic landings only. If an edit removes
            -- the owning node, keeping its old location would create exactly the
            -- kind of context-free point this module is intended to avoid.
            delete_entry_extmarks(session, entry)
            table.remove(state.history.entries, index)
            if index <= state.history.index then state.history.index = state.history.index - 1 end
        end
    end

    state.history.index = math.max(0, math.min(state.history.index, #state.history.entries))
end

---@param session AruPointJump.Session
---@param entry AruPointJump.Entry
---@param view AruPointJump.View
local function update_target(session, entry, view)
    entry.target_view = copy_view(view)
    local extmarks = session.extmarks[entry]
    extmarks.target = set_extmark(session, view, extmarks.target)
end

---@param session AruPointJump.Session
---@param view AruPointJump.View
---@param semantic AruPointJump.SemanticArea
---@return AruPointJump.Entry
local function new_entry(session, view, semantic)
    local entry = {
        anchor_view = copy_view(view),
        target_view = copy_view(view),
        semantic = semantic,
    }
    session.extmarks[entry] = {
        anchor = set_extmark(session, view),
        target = set_extmark(session, view),
    }
    return entry
end

---@param state AruPointJump.BufferState
---@param session AruPointJump.Session
---@param from number
local function truncate_history(state, session, from)
    for i = #state.history.entries, from, -1 do
        local removed = table.remove(state.history.entries, i)
        delete_entry_extmarks(session, removed)
    end
    state.history.index = math.min(state.history.index, #state.history.entries)
end

---@param history AruPointJump.History
---@param semantic AruPointJump.SemanticArea
---@param view AruPointJump.View
---@return number?
local function nearest_match(history, semantic, view)
    local best_index = nil
    local best_distance = math.huge

    for index, entry in ipairs(history.entries) do
        if entry_matches(entry, semantic, view) then
            local distance = math.abs(entry.anchor_view.lnum - view.lnum)
            if distance < best_distance then
                best_index = index
                best_distance = distance
            end
        end
    end

    return best_index
end

---@param state AruPointJump.BufferState
---@param session AruPointJump.Session
---@param view AruPointJump.View
---@return boolean recorded
local function record_point(state, session, view)
    local tick = vim.api.nvim_buf_get_changedtick(session.bufnr)
    if tick ~= session.changetick then
        sanitize_history(state, session)
        session.changetick = tick
    end

    local history = state.history
    local semantic = semantic_area_at(session.bufnr, view)
    if not semantic then return false end

    local current = history.entries[history.index]

    -- Incidental movement inside the restored/current area updates its return
    -- target without branching or destroying forward history.
    if current and entry_matches(current, semantic, view) then
        update_target(session, current, view)
        return true
    end

    -- Landing in another area from the middle is an ordinary navigation branch.
    if history.index < #history.entries then
        truncate_history(state, session, history.index + 1)
    end

    local match = nearest_match(history, semantic, view)
    if match then
        -- Revisited areas are ordered by recency. A -> B -> C -> B therefore
        -- becomes A -> C -> B, making C the previous point.
        local entry = table.remove(history.entries, match)
        update_target(session, entry, view)
        table.insert(history.entries, entry)
        history.index = #history.entries
        return true
    end

    table.insert(history.entries, new_entry(session, view, semantic))
    history.index = #history.entries

    if #history.entries > M.config.max_history then
        local removed = table.remove(history.entries, 1)
        delete_entry_extmarks(session, removed)
        history.index = #history.entries
    end

    return true
end

---@param state AruPointJump.BufferState
---@param session AruPointJump.Session
---@return boolean recorded
local function commit_current(state, session)
    session.debounce:stop()
    return record_point(state, session, capture_view())
end

---@param session AruPointJump.Session
---@param entry AruPointJump.Entry
local function restore_entry(session, entry)
    local view = copy_view(entry.target_view)
    refresh_view_from_extmark(session, session.extmarks[entry].target, view)
    vim.fn.winrestview(view)

    entry.target_view = view
    session.ignore_cursor = { lnum = view.lnum, col = view.col }
end

---@param delta number
local function move(delta)
    local bufnr = vim.api.nvim_get_current_buf()
    local path = trackable_path(bufnr)
    local state = path and M.buffers[path] or nil
    local session = state and state.session or nil
    if not state or not session or session.bufnr ~= bufnr then return end

    -- Capture a pending landing before calculating the target. This makes an
    -- immediate <C-o> after a jump behave the same as waiting for the debounce.
    local recorded = commit_current(state, session)

    -- An unclassified location is deliberately absent from history. Moving
    -- backward from it should therefore return to the latest semantic landing,
    -- not skip that landing and restore the point before it.
    local target_index = state.history.index + delta
    if delta < 0 and not recorded then target_index = state.history.index end
    if target_index < 1 or target_index > #state.history.entries then return end

    restore_entry(session, state.history.entries[target_index])
    state.history.index = target_index
end

---@param state AruPointJump.BufferState
---@param session AruPointJump.Session
local function create_buffer_autocmds(state, session)
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = M.config.augroup_id,
        buffer = session.bufnr,
        desc = "Aru point jump: capture landing after cursor settles",
        callback = function(ev)
            if not trackable_path(ev.buf) then return end

            local view = capture_view()
            if session.ignore_cursor then
                local ignored = session.ignore_cursor
                session.ignore_cursor = nil
                if view.lnum == ignored.lnum and view.col == ignored.col then return end
            end

            session.debounce:stop()
            local origin_win = vim.api.nvim_get_current_win()
            session.debounce:start(M.config.debounce_ms, 0, function()
                vim.schedule(function()
                    if
                        state.session ~= session
                        or not vim.api.nvim_win_is_valid(origin_win)
                        or vim.api.nvim_win_get_buf(origin_win) ~= session.bufnr
                        or not trackable_path(session.bufnr)
                    then
                        return
                    end

                    vim.api.nvim_win_call(
                        origin_win,
                        function() record_point(state, session, capture_view()) end
                    )
                end)
            end)
        end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        group = M.config.augroup_id,
        buffer = session.bufnr,
        desc = "Aru point jump: commit pending landing before leaving",
        callback = function()
            if state.session == session and trackable_path(session.bufnr) then
                commit_current(state, session)
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        group = M.config.augroup_id,
        buffer = session.bufnr,
        desc = "Aru point jump: release volatile buffer state",
        callback = function()
            session.debounce:stop()
            session.debounce:close()
            if state.session == session then state.session = nil end
        end,
    })
end

---@param bufnr number
local function on_buf_enter(bufnr)
    local path = trackable_path(bufnr)
    if not path then return end

    local state = M.buffers[path]
    if state and state.session and state.session.bufnr == bufnr then return end

    if not state then
        state = { history = { index = 0, entries = {} } }
        M.buffers[path] = state
    end

    local session = {
        bufnr = bufnr,
        changetick = vim.api.nvim_buf_get_changedtick(bufnr),
        debounce = assert(vim.uv.new_timer()),
        extmarks = {},
        ignore_cursor = nil,
    }
    state.session = session

    for _, entry in ipairs(state.history.entries) do
        session.extmarks[entry] = {
            anchor = set_extmark(session, entry.anchor_view),
            target = set_extmark(session, entry.target_view),
        }
    end
    sanitize_history(state, session)
    create_buffer_autocmds(state, session)

    -- Seed after BufEnter handlers have finished (for example, after a plugin
    -- restores a saved cursor). BufLeave and prev/next commit synchronously, so
    -- an immediate transition is still captured if this callback has not run.
    if #state.history.entries == 0 then
        vim.schedule(function()
            if
                state.session == session
                and vim.api.nvim_get_current_buf() == bufnr
                and #state.history.entries == 0
                and trackable_path(bufnr)
            then
                record_point(state, session, capture_view())
            end
        end)
    end
end

function M.prev() move(-1) end
function M.next() move(1) end

function M.reset()
    for _, state in pairs(M.buffers) do
        local session = state.session
        if session then
            session.debounce:stop()
            session.debounce:close()
            vim.api.nvim_buf_clear_namespace(session.bufnr, M.config.namespace, 0, -1)
            state.session = nil
        end
    end
    M.buffers = {}

    if M.config.augroup_id then
        vim.api.nvim_clear_autocmds({ group = M.config.augroup_id })
        M.config.augroup_id = nil
    end
    M.setup()
end

---@param opts AruPointJump.Config?
function M.setup(opts)
    if opts then M.config = vim.tbl_deep_extend("force", M.config, opts) end

    if not M.config.augroup_id then
        M.config.augroup_id = vim.api.nvim_create_augroup("aru_point_jump", { clear = true })
        vim.api.nvim_create_autocmd("BufEnter", {
            group = M.config.augroup_id,
            desc = "Aru point jump: initialize buffer tracking",
            callback = function(ev) on_buf_enter(ev.buf) end,
        })
    end

    on_buf_enter(vim.api.nvim_get_current_buf())
end

if vim.g.aru_test then M._test = { record_point = record_point } end

return M
