---@module "aru.core.smartjmp"
---@brief Session-aware jump history tuned for Neovim nightly
---@description
--- SmartJmp exists as the lightweight middle ground between the jumplist and
--- manual marks. It remembers the views you actually care about, ignores noise,
--- and survives a whole session.
---
--- We treat navigation as bursts, fast hops stay invisible while real leaps
--- are captured after a debounce window. The history feels intentional rather
--- than mechanical.

--- The module favors observable buffer paths over ephemeral numbers to keep
--- continuity across reloads, clamps history to a tiny ring to stay cache-hot,
--- and leans on LuaJIT- friendly data structures so you never notice it’s
--- watching.

local log = require("aru.log")

local default_config = {
    debounce_ms = 250,
    major_move_lines = 7,

    max_history = 20,
    max_file_lookback = 3,
    min_block_lines = 15,

    capture_priority = {
        ["block.outer"] = 1,
        ["function.outer"] = 2,
        ["method.outer"] = 2,
        ["class.outer"] = 4,
    },

    ---@type string[]
    exclude_filetypes = { "oil", "fzf" },
    exclude_buftypes = {
        "help",
        "nofile",
        "quickfix",
        "terminal",
        "prompt",
        "acwrite",
    },
    augroup_id = nil,
    namespace = vim.api.nvim_create_namespace("aru_smartjmp"),
}

---@class SmartJmp.Config
---@field debounce_ms number
---@field major_move_lines number
---@field max_history number
---@field max_file_lookback number
---@field min_block_lines number
---@field capture_priority table<string, number>
---@field exclude_filetypes string[]
---@field exclude_buftypes string[]
---@field augroup_id number?
---@field namespace  number

---@class SmartJmp.Module
---@field private f_hist SmartJmp.FileHistory?
---@field private buffers table<string, SmartJmp.BufferState>
---@field private suppress_cursor_moved boolean
---@field private config SmartJmp.Config
local M = {
    f_hist = nil,
    buffers = {},
    suppress_cursor_moved = false,
    config = vim.tbl_extend("force", {}, default_config),
}

---@param fn fun(): any
---@return any
local function with_suppressed_cursor_moved(fn)
    M.suppress_cursor_moved = true

    local ok, result = pcall(fn)

    M.suppress_cursor_moved = false

    if not ok then error(result) end

    return result
end

---@class SmartJmp.View :   vim.fn.winrestview.dict
---@field lnum        number
---@field col         number
---@field coladd      number
---@field curswant    number
---@field leftcol     number
---@field topline     number
---@field botline     number
---@field topfill     number
---@field skipcol     number

---@return SmartJmp.View
local function capture_view()
    return vim.tbl_extend("force", {}, vim.fn.winsaveview(), { botline = vim.fn.line("w$") })
end

---@param origin SmartJmp.View
---@param current SmartJmp.View
---@return boolean
local function is_major_move(origin, current)
    if math.abs(origin.lnum - current.lnum) > M.config.major_move_lines then return true end

    -- We check whether the current cursor position is within the original viewport
    if origin.botline < current.lnum or current.lnum < origin.topline then return true end

    return false
end

---@param t uv.uv_timer_t
local function stop_burst(t)
    if t and not t:is_closing() then t:stop() end
end

---@param bufnr number
---@return boolean
local function is_trackable_buffer(bufnr)
    if
        not bufnr
        or not vim.api.nvim_buf_is_valid(bufnr)
        or not vim.api.nvim_buf_is_loaded(bufnr)
    then
        return false
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then return false end

    local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if vim.tbl_contains(M.config.exclude_filetypes, ft) then return false end

    local bt = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
    if vim.tbl_contains(M.config.exclude_buftypes, bt) then return false end

    return true
end

---@param semantic SmartJmp.SemanticArea
---@param row number 0-indexed
---@param col number 0-indexed
---@return boolean
local function semantic_contains_position(semantic, row, col)
    if row < semantic.start_row or row > semantic.end_row then return false end
    if row == semantic.start_row and col < semantic.start_col then return false end
    if row == semantic.end_row and col > semantic.end_col then return false end

    return true
end

---@param semantic SmartJmp.SemanticArea
---@return number
local function semantic_line_count(semantic) return semantic.end_row - semantic.start_row + 1 end

---@class SmartJmp.SemanticCandidate
---@field area SmartJmp.SemanticArea?
---@field weight number
---@field line_count number

---@param candidate SmartJmp.SemanticCandidate
---@param current SmartJmp.SemanticCandidate?
---@return boolean
local function is_better_semantic_candidate(candidate, current)
    if not current then return true end
    if candidate.weight < current.weight then return true end
    if candidate.weight > current.weight then return false end

    return candidate.line_count < current.line_count
end

---@alias SmartJmp.TreesitterCapture fun(end_line?: integer, end_col?: integer): integer, TSNode, vim.treesitter.query.TSMetadata, TSQueryMatch, TSTree

---@class SmartJmp.TreesitterIterator
---@field iter SmartJmp.TreesitterCapture
---@field query vim.treesitter.Query

---@param bufnr number
---@return SmartJmp.TreesitterIterator?
local function iter_textobj_captures(bufnr)
    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then return nil end

    local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok_parser or not parser then return nil end

    local ok_parse, trees = pcall(parser.parse, parser)
    local tree = ok_parse and trees and trees[1] or nil
    local root = tree and tree:root() or nil
    if not root then return nil end

    local ok_query, query = pcall(vim.treesitter.query.get, lang, "textobjects")
    if not ok_query or not query then return nil end

    local root_start, _, root_end, _ = root:range()

    return {
        iter = query:iter_captures(root, bufnr, root_start, root_end + 1),
        query = query,
    }
end

---@param bufnr number
---@param view SmartJmp.View
---@return SmartJmp.SemanticArea?
local function semantic_area_at(bufnr, view)
    ---@type SmartJmp.SemanticCandidate?
    local best_match = nil
    local row = math.max(view.lnum - 1, 0)
    local col = math.max(view.col, 0)

    local iterator = iter_textobj_captures(bufnr)
    if not iterator then return nil end

    for id, node, _, _ in iterator.iter do
        local name = iterator.query.captures[id]

        local weight = M.config.capture_priority[name]
        if not weight then goto continue end

        local sr, sc, er, ec = node:range()
        local semantic = {
            source = "textobject",
            capture = name,
            kind = node:type(),
            start_row = sr,
            start_col = sc,
            end_row = er,
            end_col = ec,
        }

        ---@type SmartJmp.SemanticCandidate
        local candidate = {
            area = semantic,
            weight = weight,
            line_count = semantic_line_count(semantic),
        }

        if
            not (
                semantic.capture == "block.outer"
                and candidate.line_count < M.config.min_block_lines
            ) and semantic_contains_position(semantic, row, col)
        then
            if is_better_semantic_candidate(candidate, best_match) then best_match = candidate end
        end

        ::continue::
    end

    if best_match then return best_match.area end

    return nil
end

---@param area SmartJmp.SemanticArea
---@param current SmartJmp.SemanticArea
---@return boolean
local function same_semantic_area(area, current)
    if area.capture ~= current.capture then return false end
    if area.kind ~= current.kind then return false end

    if area.start_row <= current.start_row and current.start_row <= area.end_row then
        return true
    end
    if current.start_row <= area.start_row and area.start_row <= current.end_row then
        return true
    end

    return math.abs(area.start_row - current.start_row) <= 5
end

---@param area SmartJmp.Area
---@param bufnr number
---@param view SmartJmp.View
---@return boolean
local function area_matches_view(area, bufnr, view)
    local current_semantic = semantic_area_at(bufnr, view)

    if area.semantic and current_semantic then
        return same_semantic_area(area.semantic, current_semantic)
    end

    return not is_major_move(area.view, view)
end

---@class SmartJmp.SemanticArea
---@field source string "textobject"|"node"|"fallback"
---@field capture string?
---@field kind string
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number

---@class SmartJmp.Area
---@field path string
---@field bufnr number?
---@field view SmartJmp.View
---@field latest_view SmartJmp.View
---@field semantic SmartJmp.SemanticArea?

---@param bufnr number
---@param view SmartJmp.View
---@return SmartJmp.Area
local function area_from_view(bufnr, view)
    return {
        path = vim.api.nvim_buf_get_name(bufnr),
        bufnr = bufnr,
        view = vim.tbl_extend("force", {}, view),
        latest_view = vim.tbl_extend("force", {}, view),
        semantic = semantic_area_at(bufnr, view),
    }
end

---@class SmartJmp.JumpPoint :   vim.fn.winrestview.dict
---@field path  string
---@field bufnr number?
---@field view  SmartJmp.View
---@field extmark_id number?
---@field semantic SmartJmp.SemanticArea?

---@param point SmartJmp.JumpPoint
---@param extmark_id number?
---@return number extmark_id
local function set_point_extmark(point, extmark_id)
    local view = point.view

    local line_count = vim.api.nvim_buf_line_count(point.bufnr)
    local row = math.min(math.max(view.lnum - 1, 0), math.max(line_count - 1, 0))
    local line = vim.api.nvim_buf_get_lines(point.bufnr, row, row + 1, false)[1] or ""
    local col = math.min(math.max(view.col, 0), #line)

    local opts = {
        right_gravity = true,
        end_row = row,
        end_col = math.min(#line, col + 1),
    }
    if extmark_id then opts.id = extmark_id end

    return vim.api.nvim_buf_set_extmark(point.bufnr, M.config.namespace, row, col, opts)
end

---@param area SmartJmp.Area
---@param source string
---@return SmartJmp.JumpPoint
local function jump_point_from_area(area, source)
    return {
        path = area.path,
        bufnr = area.bufnr,
        view = vim.tbl_extend("force", {}, area.latest_view or area.view),
        semantic = area.semantic,
        source = source,
    }
end

---@param path string
---@param bufnr number?
---@return number? bufnr
---@return boolean cache_valid
local function ensure_buffer_loaded(path, bufnr)
    if not path or path == "" then return nil, false end

    if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == path then
        return bufnr, true
    end

    -- We have to check whether the buffer path exists in the current session,
    -- if we get here we know that the bufnr is not valid anymore. But we have
    -- to guarantee that we don't have the same buffer loaded twice.
    local existing = vim.fn.bufnr(path)
    if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then return existing, false end

    -- Now it's whether the file even exists anymore, if it does we have to load
    -- it in the current session to get a valid bufnr that we can use again.
    local stat = vim.uv.fs_stat(path)
    if not stat or stat.type ~= "file" then
        log:warn(("restore: invalid file for %s"):format(path))
        return nil, false
    end

    -- At this point we know that the file exists and we can load it in the current
    -- session, we just have to ensure that it loaded successfully to avoid any
    -- race conditions.
    local new_bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(new_bufnr)

    if not vim.api.nvim_buf_is_valid(new_bufnr) or not vim.api.nvim_buf_is_loaded(new_bufnr) then
        return nil, false
    end

    return new_bufnr, false
end

---@param point SmartJmp.JumpPoint
---@return boolean extmark_valid
local function load_buffer_view(point)
    local extmark_valid = false

    if point.extmark_id then
        local ok, pos = pcall(
            vim.api.nvim_buf_get_extmark_by_id,
            point.bufnr,
            M.config.namespace,
            point.extmark_id,
            {}
        )
        if ok and pos[1] then
            -- remember, neovim extmarks are 0-indexed, so we add +1 to match
            -- other editor behaviour.
            point.view.lnum = pos[1] + 1
            point.view.col = pos[2]

            extmark_valid = true
        else
            log:warn(("restore: extmark %d deleted for %s"):format(point.extmark_id, point.path))
        end
    end

    vim.fn.winrestview(point.view)

    return extmark_valid
end

---@class SmartJmp.History
---@field entries SmartJmp.JumpPoint[]
---@field index number
---@field add fun(self: SmartJmp.History, point: SmartJmp.JumpPoint)
---@field move fun(self: SmartJmp.History, delta: number): SmartJmp.JumpPoint?
local History = {}
History.__index = History

---@return SmartJmp.History
function History:new()
    return setmetatable({
        entries = {},
        index = 0,
    }, History)
end

---@return SmartJmp.JumpPoint?
function History:current() return self.entries[self.index] end

function History:truncate()
    if self.index == #self.entries then return end

    -- We have to do a reverse iteration to avoid modifying the table in place,
    -- this ensures that we don't mess up the index.
    for i = #self.entries, self.index + 1, -1 do
        local point = self.entries[i]
        if point.bufnr and point.extmark_id and vim.api.nvim_buf_is_valid(point.bufnr) then
            pcall(vim.api.nvim_buf_del_extmark, point.bufnr, M.config.namespace, point.extmark_id)
        end

        table.remove(self.entries, i)
    end

    assert(self.index == #self.entries)
end

---@param index number
---@param point SmartJmp.JumpPoint
function History:update(index, point)
    if index < 1 or index > #self.entries then
        log:warn(("update: invalid index %d for %d entries"):format(index, #self.entries))
        return
    end

    local existing = self.entries[index]
    point.extmark_id = set_point_extmark(point, existing.extmark_id)

    self.entries[index] = point
end

---@param point SmartJmp.JumpPoint
function History:add(point)
    self:truncate()

    if not point.bufnr or not is_trackable_buffer(point.bufnr) then
        log:warn(("add: invalid buffer for %s"):format(point.path))
        return
    end

    -- Naive check if we already have this view in history.
    local last = self.entries[#self.entries]
    if last and last.path == point.path and not is_major_move(last.view, point.view) then
        if last.bufnr and last.extmark_id and vim.api.nvim_buf_is_valid(last.bufnr) then
            pcall(vim.api.nvim_buf_del_extmark, last.bufnr, M.config.namespace, last.extmark_id)
        end

        self.entries[#self.entries] = nil
    end

    point.extmark_id = set_point_extmark(point)

    -- We add the point to history entries and if we exceed the max history we
    -- prune the oldest entry. This ensures we don't grow unbounded.
    table.insert(self.entries, point)
    if #self.entries > M.config.max_history then
        local removed = table.remove(self.entries, 1)
        if
            removed
            and removed.bufnr
            and removed.extmark_id
            and vim.api.nvim_buf_is_valid(removed.bufnr)
        then
            pcall(
                vim.api.nvim_buf_del_extmark,
                removed.bufnr,
                M.config.namespace,
                removed.extmark_id
            )
        end
    end

    self.index = #self.entries
end

---@param point SmartJmp.JumpPoint
---@return boolean restored
function History:restore(point)
    -- this will fail if the buffer doesn't exist or isn't loaded
    if not point or not point.view then
        log:warn("restore: invalid point / buffer")
        return false
    end

    -- update the point to reflect whatever buffer we've just loaded, if the buffer
    -- is the same or changed doesn't really matter, we just update it regardless.
    local bufnr = vim.api.nvim_get_current_buf()
    if point.bufnr ~= bufnr then point.bufnr = bufnr end

    local extmark_valid = with_suppressed_cursor_moved(
        function() return load_buffer_view(point) end
    )
    if point.extmark_id and not extmark_valid then point.extmark_id = nil end

    return true
end

---@param delta number
---@return SmartJmp.JumpPoint? point
function History:move(delta)
    log:trace(("move: jump idx=%d delta=%d"):format(self.index, delta))

    local target_index = self.index + delta

    -- We don't want to move outside the bounds of the history.
    if target_index < 1 or target_index > #self.entries then
        log:trace(("move: invalid index %d for %d entries"):format(target_index, #self.entries))
        return
    end

    -- We get the point that we want to restore and try to restore it, if it fails
    -- we have a "stale" point, and it needs to be removed from the history to ensure
    -- we don't end up with dead points that can't be used.
    --
    -- This means we have a bit of a dirty side effect here, but it's a decent tradeoff
    -- to avoid having to deal with stale points.
    local point = self.entries[target_index]
    local ok = self:restore(point)
    if not ok then
        log:trace(("move: failed to restore %s"):format(point and point.path or "<invalid>"))
        table.remove(self.entries, target_index)

        -- After removing a stale point we need to ensure that our internal index
        -- maintains it's current position, if we remove +1 self.index is maintained,
        -- if we remove -1 self.index will need to be decremented.
        if delta < 0 then self.index = math.max(0, self.index - 1) end
        self.index = math.min(self.index, #self.entries)

        return nil
    end

    -- Only update the index if we've successfully restored the point, otherwise
    self.index = target_index

    return point
end

---@param point SmartJmp.JumpPoint
---@param area SmartJmp.Area
---@return boolean
local function jump_point_matches_area(point, area)
    if point.path ~= area.path then return false end

    if point.semantic and area.semantic then
        return same_semantic_area(point.semantic, area.semantic)
    end

    return not is_major_move(point.view, area.latest_view or area.view)
end

---@class SmartJmp.FileState
---@field path string
---@field bufnr number?

---@class SmartJmp.FileHistory
---@field index number
---@field entries SmartJmp.FileState[]
local FileHistory = {}
FileHistory.__index = FileHistory

---@return SmartJmp.FileHistory
function FileHistory:new()
    return setmetatable({
        index = 0,
        entries = {},
    }, FileHistory)
end

M.f_hist = FileHistory:new()

---@return SmartJmp.FileState?
function FileHistory:current() return self.entries[self.index] end

function FileHistory:truncate()
    if self.index == #self.entries then return end

    for i = #self.entries, self.index + 1, -1 do
        table.remove(self.entries, i)
    end

    assert(self.index == #self.entries)
end

--- Scans the history stack backwards to see if a file path already exists.
---
---@param path string
---@return boolean
function FileHistory:contains(path)
    if self.index == 0 then return false end

    -- Ensure that we don't scan too far back in the history, by taking the
    -- minimum of the configured `max_file_lookback` and the current index.
    local lower = math.max(1, self.index - M.config.max_file_lookback + 1)

    for i = self.index, lower, -1 do
        local entry = self.entries[i]
        if entry.path == path then return true end
    end

    return false
end

---@param bufnr number
---@return SmartJmp.FileState?
function FileHistory:add(bufnr)
    -- To ensure that our list is always sorted and does not carry
    -- any stale entries, we truncate before adding new entries.
    self:truncate()

    local path = vim.api.nvim_buf_get_name(bufnr) or ""
    if path == "" or not is_trackable_buffer(bufnr) then
        log:warn(("add: invalid buffer, %d does not point to a path."):format(bufnr))
        return nil
    end

    if self:contains(path) then return nil end

    ---@type SmartJmp.FileState
    local state = {
        path = path,
        bufnr = bufnr,
    }

    self.index = #self.entries + 1
    self.entries[self.index] = state

    return state
end

---@param bufnr number
function FileHistory:add_if_current_differs(bufnr)
    local current = self:current()
    local path = vim.api.nvim_buf_get_name(bufnr)
    if current and current.path == path then return end

    self:add(bufnr)
end

---@param delta number
---@return SmartJmp.FileState?
function FileHistory:move(delta)
    local target_index = self.index + delta
    if target_index < 1 or target_index > #self.entries then
        log:warn(("move: invalid index %d for %d entries"):format(target_index, #self.entries))
        return nil
    end

    local state = self.entries[target_index]

    -- After we've ensured that the point has a valid buffer we need to update
    -- any point that has invalidated cache. If a invalid cache is found extmark_ids
    -- needs to be cleared as they are memory bound and unusable after a reload.
    local bufnr, cache_hit = ensure_buffer_loaded(state.path, state.bufnr)
    if not bufnr then
        log:warn(("restore: invalid buffer for %s"):format(state.path))

        -- If we fail to restore the buffer we need to remove the entry from
        -- history, it's stale and we only want to keep entries we can
        -- successfully restore.
        table.remove(self.entries, target_index)
        if delta < 0 then self.index = math.max(0, self.index - 1) end

        return nil
    end

    if not cache_hit then state.bufnr = bufnr end

    -- Finally we have to focus the buffer in case it's not the current buffer.
    if vim.api.nvim_get_current_buf() ~= state.bufnr then
        vim.api.nvim_set_current_buf(state.bufnr)
    end

    -- To avoid messing with the `BufferState` we restore the "active" point
    -- in the history, if there is one.
    local buf_state = M.buffers[state.path]
    if buf_state then
        local point = buf_state.history:current()
        if point then buf_state.history:restore(point) end
    end

    self.index = target_index

    return state
end

---@class SmartJmp.BufferState
---@field path string
---@field bufnr number?
---@field debounce uv.uv_timer_t?
---@field history SmartJmp.History
---@field area SmartJmp.Area?
local BufferState = {}
BufferState.__index = BufferState

---@param bufnr number
---@return SmartJmp.BufferState
function BufferState:new(bufnr)
    local path = vim.api.nvim_buf_get_name(bufnr)
    assert(type(path) == "string")
    assert(path ~= "")

    local timer = vim.uv.new_timer()
    assert(timer)

    return setmetatable({
        path = path,
        bufnr = bufnr,
        debounce = timer,
        history = History:new(),
        area = nil,
    }, BufferState)
end

---@param bufnr number
local function create_cursor_move_autocmd(bufnr)
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = M.config.augroup_id,
        buffer = bufnr,
        desc = "",
        callback = function(ev)
            if M.suppress_cursor_moved then return end

            -- We only want to handle cursor moved events for buffers that we
            -- are tracking, if we're not tracking the buffer we can just bail.
            if not is_trackable_buffer(ev.buf) then return end

            -- If we don't have a state at this point something is wrong, this
            -- should be setup in the `on_buf_enter` callback. Essentially, this
            -- shouldn't happen, but we are defensive!
            local state = M.buffers[vim.api.nvim_buf_get_name(ev.buf)]
            if not state then return end

            local origin_buf = ev.buf
            local origin_win = vim.api.nvim_get_current_win()
            local origin_path = vim.api.nvim_buf_get_name(origin_buf)

            local timer = state.debounce
            if not timer then return end
            if timer:is_active() then timer:stop() end

            timer:start(M.config.debounce_ms, 0, function()
                vim.schedule(function()
                    -- Things might change between the time we start the debounce
                    -- and the time we stop it, so we need to ensure that we have
                    -- a valid state and timer.
                    local state = M.buffers[origin_path]
                    if not state then return end
                    local timer = state.debounce
                    if not timer then return end

                    -- Ensure that we are still in the original window and that
                    -- nothing has changed with the buffer in the meantime. It's
                    -- should be handled by our `BufferLeave` event, but we are
                    -- defensive!
                    if
                        not vim.api.nvim_win_is_valid(origin_win)
                        or vim.api.nvim_win_get_buf(origin_win) ~= origin_buf
                        or not is_trackable_buffer(origin_buf)
                    then
                        stop_burst(timer)
                        return
                    end

                    -- To the meat, if we've passed all checks we can now safely
                    -- capture the current view and add it to our history.
                    vim.api.nvim_win_call(origin_win, function()
                        local current = capture_view()

                        -- If this is the first view we've captured we need to
                        -- create a new area and store it in our current area
                        if not state.area then
                            state.area = area_from_view(origin_buf, current)
                            state.history:add(jump_point_from_area(state.area, "area-entered"))
                        else
                            if area_matches_view(state.area, origin_buf, current) then
                                state.area.latest_view = current

                                local current_point = state.history:current()
                                if current_point and jump_point_matches_area(current_point, state.area) then
                                    state.history:update(
                                        state.history.index,
                                        jump_point_from_area(state.area, "area-updated")
                                    )
                                end
                            else
                                state.area = area_from_view(origin_buf, current)
                                state.history:add(jump_point_from_area(state.area, "area-entered"))
                            end
                        end
                    end)

                    stop_burst(timer)
                end)
            end)
        end,
    })
end

---@param bufnr number
local function create_buf_wipeout_autocmd(bufnr)
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = M.config.augroup_id,
        buffer = bufnr,
        desc = "Cleanup our buffer timer when a buffer get's wiped."
            .. "We maintain all state throughout the session.",
        callback = function(ev)
            local state = M.buffers[vim.api.nvim_buf_get_name(ev.buf)]
            if not state then return end

            if state.debounce then
                -- We stop the timer but keep the reference alive if we need to
                -- reactivate it, which will happen in `on_buf_enter`.
                stop_burst(state.debounce)
                state.debounce:close()

                state.debounce = nil
                state.bufnr = nil
            end

            -- We also need to clean up the history points, not remove them but
            -- ensure that information that will change when we reload the buffer
            -- is cleared.
            for _, point in ipairs(state.history.entries) do
                if point.bufnr == ev.buf then
                    point.bufnr = nil
                    point.extmark_id = nil
                end
            end

            if state.area and state.area.bufnr == ev.buf then state.area.bufnr = nil end
        end,
    })
end

---@param bufnr number
local function create_buf_leave_autocmd(bufnr)
    vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
        group = M.config.augroup_id,
        buffer = bufnr,
        desc = "Cancel any pending jumps when a buffer or window is left.",
        callback = function()
            local state = M.buffers[vim.api.nvim_buf_get_name(bufnr)]
            if state then stop_burst(state.debounce) end
        end,
    })
end

---@param bufnr number
local function on_buf_enter(bufnr)
    -- We go fairly hard in our exclusion, we don't want to mess with buffers
    -- that shouldn't have any jump points.
    local path = vim.api.nvim_buf_get_name(bufnr)
    if not is_trackable_buffer(bufnr) then
        log:trace(("on_buf_enter: excluded %s"):format(path))
        return
    end

    local state = M.buffers[path]
    if not state then
        state = BufferState:new(bufnr)
        M.buffers[state.path] = state
    else
        if
            bufnr
            and state.bufnr == bufnr
            and vim.api.nvim_buf_is_valid(bufnr)
            and state.debounce
            and not state.debounce:is_closing()
        then
            return
        end

        -- If we don't have a debounce timer or it's closing we need to create
        -- a new one. This shouldn't really be happening, but we are defensive!
        if not state.debounce or state.debounce:is_closing() then
            state.debounce = assert(vim.uv.new_timer())
        end

        state.bufnr = bufnr
    end

    create_cursor_move_autocmd(bufnr)
    create_buf_wipeout_autocmd(bufnr)
    create_buf_leave_autocmd(bufnr)
end

---@param delta number
local function file_move(delta)
    -- We start by recording a navigation point for the current file. After we
    -- have performed the navigation we try to add a new entry to the history
    -- stack, this might fail if the current file is already in the history.
    -- which is expected.

    local bufnr = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(bufnr)

    -- If we're moving back in the list we need to add the current buffer to the
    -- history, this is expected and wanted.
    if delta < 0 then M.f_hist:add_if_current_differs(bufnr) end

    local trg_state = M.f_hist:move(delta)
    if not trg_state then log:warn(("move: failed navigation to buffer %s"):format(path)) end
end

---@param delta number
local function buffer_move(delta)
    local bufnr = vim.api.nvim_get_current_buf()
    local state = M.buffers[vim.api.nvim_buf_get_name(bufnr)]

    if not (state and state.area) then return end

    local point = state.history:move(delta)
    if not point then return end

    -- History:move restores first and may refresh point.view from its extmark,
    -- so rebuilding state.area here anchors tracking at the actual restored location.
    state.area = area_from_view(point.bufnr, point.view)
end

---@param bufnr number?
function M.file_mark(bufnr) M.f_hist:add(bufnr or vim.api.nvim_get_current_buf()) end
function M.file_next() file_move(1) end
function M.file_prev() file_move(-1) end

function M.with_file_mark(fn)
    return function()
        M.file_mark(vim.api.nvim_get_current_buf())
        return fn()
    end
end

function M.file_toggle()
    if M.f_hist.index < #M.f_hist.entries then
        file_move(1)
    else
        file_move(-1)
    end
end

function M.next() buffer_move(1) end
function M.prev() buffer_move(-1) end

function M.reset()
    log:trace(("reset: states for %d buffers"):format(vim.tbl_count(M.buffers)))

    for _, state in pairs(M.buffers) do
        if state and state.debounce and not state.debounce:is_closing() then
            state.debounce:stop()
            state.debounce:close()
        end

        if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
            vim.api.nvim_clear_autocmds({
                buffer = state.bufnr,
                group = M.config.augroup_id,
            })
        end
    end

    M.buffers = {}
    M.f_hist = FileHistory:new()

    on_buf_enter(vim.api.nvim_get_current_buf())
end

function M.setup()
    if not M.config.augroup_id then
        M.config.augroup_id = vim.api.nvim_create_augroup("aru_smartjmp", { clear = true })

        vim.api.nvim_create_autocmd("BufEnter", {
            group = M.config.augroup_id,
            desc = "",
            callback = function(ev) on_buf_enter(ev.buf) end,
        })

        on_buf_enter(vim.api.nvim_get_current_buf())
    end
end

return M
