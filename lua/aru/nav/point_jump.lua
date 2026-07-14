---@module "aru.nav.point_jump"
---@brief Buffer-local semantic jump history.
---
--- A point belongs to a Treesitter-backed editing area when possible. Small
--- semantic nodes own one point; large nodes may own several bounded local
--- areas. Each entry has a fixed area anchor and a mutable return target, so
--- revisiting an area updates its landing position without allowing the area
--- itself to drift through the buffer.

local buf = require("aru.buf")
local log = require("aru.log")
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
---@field anchor_extmark_id number?
---@field target_extmark_id number?
---@field anchor_view AruPointJump.View
---@field target_view AruPointJump.View
---@field semantic AruPointJump.SemanticArea

---@class AruPointJump.History
---@field index number
---@field entries AruPointJump.Entry[]

---@class AruPointJump.BufferState
---@field path string
---@field bufnr number?
---@field changetick number
---@field debounce uv.uv_timer_t?
---@field history AruPointJump.History
---@field ignore_cursor AruPointJump.View?

---@type table<string, AruPointJump.BufferState>
M.buffers = {}

local function copy_view(view) return vim.tbl_extend("force", {}, view) end

---@return AruPointJump.View
local function capture_view()
    return vim.tbl_extend("force", {}, vim.fn.winsaveview(), { botline = vim.fn.line("w$") })
end

---@param bufnr number
---@return string?
local function buffer_path(bufnr) return buf.normal_file_path(bufnr) end

---@param bufnr number
---@return boolean
local function is_trackable_buffer(bufnr)
    if not buf.is_loaded(bufnr) or not buffer_path(bufnr) then return false end

    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if vim.tbl_contains(M.config.exclude_filetypes, filetype) then return false end

    return not quick_close.is_quick_close_buffer(bufnr)
end

---@param timer uv.uv_timer_t?
local function stop_timer(timer)
    if timer and not timer:is_closing() then timer:stop() end
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

    local row = math.max(view.lnum - 1, 0)
    local col = math.max(view.col, 0)
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
---@param semantic AruPointJump.SemanticArea?
---@param view AruPointJump.View
---@return boolean
local function entry_matches(entry, semantic, view)
    if not entry.semantic or not semantic then return false end
    if not same_semantic_area(entry.semantic, semantic) then return false end

    if
        semantic_line_count(entry.semantic) <= M.config.max_semantic_area_lines
        and semantic_line_count(semantic) <= M.config.max_semantic_area_lines
    then
        return true
    end

    return math.abs(entry.anchor_view.lnum - view.lnum) <= M.config.locality_lines
end

---@param bufnr number
---@param view AruPointJump.View
---@param extmark_id number?
---@return number?
local function set_extmark(bufnr, view, extmark_id)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local row = math.min(math.max(view.lnum - 1, 0), math.max(line_count - 1, 0))
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
    local col = math.min(math.max(view.col, 0), #line)
    local opts = {
        id = extmark_id,
        right_gravity = true,
        end_row = row,
        end_col = math.min(col + 1, #line),
        end_right_gravity = true,
    }
    if not extmark_id then opts.id = nil end

    local ok, result =
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.config.namespace, row, col, opts)
    if not ok then
        log:warn("point_jump: failed to set extmark in %s", vim.api.nvim_buf_get_name(bufnr))
        return nil
    end
    return result
end

---@param bufnr number?
---@param extmark_id number?
local function delete_extmark(bufnr, extmark_id)
    if bufnr and extmark_id and vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, M.config.namespace, extmark_id)
    end
end

---@param state AruPointJump.BufferState
---@param entry AruPointJump.Entry
local function delete_entry_extmarks(state, entry)
    delete_extmark(state.bufnr, entry.anchor_extmark_id)
    delete_extmark(state.bufnr, entry.target_extmark_id)
end

---@param state AruPointJump.BufferState
---@param extmark_id number?
---@param view AruPointJump.View
---@return boolean
local function refresh_view_from_extmark(state, extmark_id, view)
    if not state.bufnr or not extmark_id then return false end
    local ok, pos =
        pcall(vim.api.nvim_buf_get_extmark_by_id, state.bufnr, M.config.namespace, extmark_id, {})
    if not ok or not pos[1] then return false end

    local old_lnum = view.lnum
    view.lnum = pos[1] + 1
    view.col = pos[2]

    -- Keep the saved viewport moving with the cursor anchor when edits happen
    -- above it. Extmarks track the cursor itself, not winsaveview()'s topline.
    local delta = view.lnum - old_lnum
    if view.topline then view.topline = math.max(1, view.topline + delta) end
    if view.botline then view.botline = math.max(1, view.botline + delta) end

    return true
end

---@param state AruPointJump.BufferState
local function sanitize_history(state)
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end

    for index = #state.history.entries, 1, -1 do
        local entry = state.history.entries[index]
        if entry.anchor_extmark_id then
            if
                not refresh_view_from_extmark(state, entry.anchor_extmark_id, entry.anchor_view)
            then
                entry.anchor_extmark_id = nil
            end
        end
        if entry.target_extmark_id then
            if
                not refresh_view_from_extmark(state, entry.target_extmark_id, entry.target_view)
            then
                entry.target_extmark_id = nil
            end
        end

        local semantic = semantic_area_at(state.bufnr, entry.anchor_view)
        if semantic then
            entry.semantic = semantic
        else
            -- Point history contains semantic landings only. If an edit removes
            -- the owning node, keeping its old location would create exactly the
            -- kind of context-free point this module is intended to avoid.
            delete_entry_extmarks(state, entry)
            table.remove(state.history.entries, index)
            if index <= state.history.index then state.history.index = state.history.index - 1 end
        end
    end

    state.history.index = math.max(0, math.min(state.history.index, #state.history.entries))
end

---@param state AruPointJump.BufferState
local function maybe_sanitize_history(state)
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
    local tick = vim.api.nvim_buf_get_changedtick(state.bufnr)
    if tick == state.changetick then return end

    sanitize_history(state)
    state.changetick = tick
end

---@param state AruPointJump.BufferState
---@param entry AruPointJump.Entry
local function update_target(state, entry, view)
    entry.target_view = copy_view(view)
    entry.target_extmark_id = set_extmark(state.bufnr, view, entry.target_extmark_id)
end

---@param state AruPointJump.BufferState
---@param view AruPointJump.View
---@param semantic AruPointJump.SemanticArea
---@return AruPointJump.Entry
local function new_entry(state, view, semantic)
    return {
        anchor_view = copy_view(view),
        target_view = copy_view(view),
        anchor_extmark_id = set_extmark(state.bufnr, view),
        target_extmark_id = set_extmark(state.bufnr, view),
        semantic = semantic,
    }
end

---@param state AruPointJump.BufferState
---@param from number
local function truncate_history(state, from)
    for i = #state.history.entries, from, -1 do
        local removed = table.remove(state.history.entries, i)
        if removed then delete_entry_extmarks(state, removed) end
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
---@param view AruPointJump.View
---@return boolean recorded
local function record_point(state, view)
    if not state.bufnr or not is_trackable_buffer(state.bufnr) then return false end
    maybe_sanitize_history(state)

    local history = state.history
    local semantic = semantic_area_at(state.bufnr, view)
    if not semantic then return false end

    local current = history.entries[history.index]

    -- Incidental movement inside the restored/current area updates its return
    -- target without branching or destroying forward history.
    if current and entry_matches(current, semantic, view) then
        update_target(state, current, view)
        return true
    end

    -- Landing in another area from the middle is an ordinary navigation branch.
    if history.index < #history.entries then truncate_history(state, history.index + 1) end

    local match = nearest_match(history, semantic, view)
    if match then
        -- Revisited areas are ordered by recency. A -> B -> C -> B therefore
        -- becomes A -> C -> B, making C the previous point.
        local entry = table.remove(history.entries, match)
        update_target(state, entry, view)
        table.insert(history.entries, entry)
        history.index = #history.entries
        return true
    end

    table.insert(history.entries, new_entry(state, view, semantic))
    history.index = #history.entries

    if #history.entries > M.config.max_history then
        local removed = table.remove(history.entries, 1)
        delete_entry_extmarks(state, removed)
        history.index = #history.entries
    end

    return true
end

---@param state AruPointJump.BufferState
---@return boolean recorded
local function commit_current(state)
    stop_timer(state.debounce)
    if
        not state.bufnr
        or vim.api.nvim_get_current_buf() ~= state.bufnr
        or not is_trackable_buffer(state.bufnr)
    then
        return false
    end

    return record_point(state, capture_view())
end

---@param view AruPointJump.View
---@param bufnr number
local function clamp_view(view, bufnr)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    view.lnum = math.min(math.max(view.lnum or 1, 1), math.max(line_count, 1))
    local line = vim.api.nvim_buf_get_lines(bufnr, view.lnum - 1, view.lnum, false)[1] or ""
    view.col = math.min(math.max(view.col or 0, 0), #line)
    view.topline = math.min(math.max(view.topline or view.lnum, 1), math.max(line_count, 1))
end

---@param state AruPointJump.BufferState
---@param entry AruPointJump.Entry
---@return boolean
local function restore_entry(state, entry)
    if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return false end

    local view = copy_view(entry.target_view)
    refresh_view_from_extmark(state, entry.target_extmark_id, view)
    clamp_view(view, state.bufnr)

    local ok = pcall(vim.fn.winrestview, view)
    if not ok then
        log:warn("point_jump: failed to restore %s at %d:%d", state.path, view.lnum, view.col)
        return false
    end

    entry.target_view = view
    state.ignore_cursor = { lnum = view.lnum, col = view.col }
    return true
end

---@param delta number
local function move(delta)
    local bufnr = vim.api.nvim_get_current_buf()
    local path = buffer_path(bufnr)
    local state = path and M.buffers[path] or nil
    if not state then return end

    -- Capture a pending landing before calculating the target. This makes an
    -- immediate <C-o> after a jump behave the same as waiting for the debounce.
    local recorded = commit_current(state)
    maybe_sanitize_history(state)

    -- An unclassified location is deliberately absent from history. Moving
    -- backward from it should therefore return to the latest semantic landing,
    -- not skip that landing and restore the point before it.
    local target_index = state.history.index + delta
    if delta < 0 and not recorded then target_index = state.history.index end
    if target_index < 1 or target_index > #state.history.entries then return end

    local entry = state.history.entries[target_index]
    if restore_entry(state, entry) then state.history.index = target_index end
end

---@param state AruPointJump.BufferState
---@param bufnr number
local function create_buffer_autocmds(state, bufnr)
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = M.config.augroup_id,
        buffer = bufnr,
        desc = "Aru point jump: capture landing after cursor settles",
        callback = function(ev)
            if not is_trackable_buffer(ev.buf) then return end

            local view = capture_view()
            if state.ignore_cursor then
                local ignored = state.ignore_cursor
                state.ignore_cursor = nil
                if view.lnum == ignored.lnum and view.col == ignored.col then return end
            end

            local timer = state.debounce
            if not timer or timer:is_closing() then return end
            stop_timer(timer)

            local origin_win = vim.api.nvim_get_current_win()
            timer:start(M.config.debounce_ms, 0, function()
                vim.schedule(function()
                    if
                        state.debounce ~= timer
                        or timer:is_closing()
                        or not state.bufnr
                        or not vim.api.nvim_win_is_valid(origin_win)
                        or vim.api.nvim_win_get_buf(origin_win) ~= state.bufnr
                    then
                        return
                    end

                    vim.api.nvim_win_call(
                        origin_win,
                        function() record_point(state, capture_view()) end
                    )
                    stop_timer(timer)
                end)
            end)
        end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        group = M.config.augroup_id,
        buffer = bufnr,
        desc = "Aru point jump: commit pending landing before leaving",
        callback = function() commit_current(state) end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        group = M.config.augroup_id,
        buffer = bufnr,
        desc = "Aru point jump: release volatile buffer state",
        callback = function()
            stop_timer(state.debounce)
            if state.debounce and not state.debounce:is_closing() then state.debounce:close() end
            state.debounce = nil
            state.bufnr = nil
            state.ignore_cursor = nil
            for _, entry in ipairs(state.history.entries) do
                entry.anchor_extmark_id = nil
                entry.target_extmark_id = nil
            end
        end,
    })
end

---@param bufnr number
local function on_buf_enter(bufnr)
    if not is_trackable_buffer(bufnr) then return end
    local path = buffer_path(bufnr)
    if not path then return end

    local state = M.buffers[path]
    if state and state.bufnr == bufnr and state.debounce and not state.debounce:is_closing() then
        return
    end

    if not state then
        state = {
            path = path,
            bufnr = bufnr,
            changetick = vim.api.nvim_buf_get_changedtick(bufnr),
            debounce = assert(vim.uv.new_timer()),
            history = { index = 0, entries = {} },
            ignore_cursor = nil,
        }
        M.buffers[path] = state
    else
        state.bufnr = bufnr
        state.changetick = vim.api.nvim_buf_get_changedtick(bufnr)
        state.debounce = assert(vim.uv.new_timer())
        state.ignore_cursor = nil

        for _, entry in ipairs(state.history.entries) do
            entry.anchor_extmark_id = set_extmark(bufnr, entry.anchor_view)
            entry.target_extmark_id = set_extmark(bufnr, entry.target_view)
        end
        sanitize_history(state)
    end

    create_buffer_autocmds(state, bufnr)

    -- Seed after BufEnter handlers have finished (for example, after a plugin
    -- restores a saved cursor). BufLeave and prev/next commit synchronously, so
    -- an immediate transition is still captured if this callback has not run.
    if #state.history.entries == 0 then
        vim.schedule(function()
            if
                state.bufnr == bufnr
                and vim.api.nvim_get_current_buf() == bufnr
                and #state.history.entries == 0
                and is_trackable_buffer(bufnr)
            then
                record_point(state, capture_view())
            end
        end)
    end
end

function M.prev() move(-1) end
function M.next() move(1) end

function M.reset()
    for _, state in pairs(M.buffers) do
        stop_timer(state.debounce)
        if state.debounce and not state.debounce:is_closing() then state.debounce:close() end
        state.debounce = nil

        if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
            pcall(vim.api.nvim_buf_clear_namespace, state.bufnr, M.config.namespace, 0, -1)
        end
        state.bufnr = nil
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

local function history_debug(history)
    local parts = {}
    for index, entry in ipairs(history.entries) do
        local semantic = entry.semantic
        local label = semantic.name or semantic.kind or semantic.capture
        parts[#parts + 1] = ("%s%d:%s@%d:%d"):format(
            index == history.index and "*" or "",
            index,
            label,
            entry.target_view.lnum,
            entry.target_view.col
        )
    end
    return table.concat(parts, " ")
end

if vim.g.aru_test then
    M._test = {
        buffer_path = buffer_path,
        entry_matches = entry_matches,
        history_debug = history_debug,
        on_buf_enter = on_buf_enter,
        record_point = record_point,
        semantic_area_at = semantic_area_at,
    }
end

return M
