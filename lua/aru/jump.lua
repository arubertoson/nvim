---@module "aru.core.smartjmp"
---@brief Session-aware jump history tuned for Neovim nightly
---@description
--- SmartJmp exists as the lightweight middle ground between the jumplist and
--- manual marks. It keeps two separate histories:
---
--- 1. buffer-local semantic jump history, captured automatically after cursor
---    movement settles.
--- 2. deliberate file history, marked explicitly before actions that may leave
---    the current work area.
---
--- We treat navigation as bursts, fast hops stay invisible while real leaps
--- are captured after a debounce window. The history feels intentional rather
--- than mechanical.

--- The module favors observable buffer paths over ephemeral numbers to keep
--- continuity across reloads, clamps history to a tiny ring to stay cache-hot,
--- and leans on LuaJIT-friendly data structures so you never notice it’s
--- watching.

local log = require("aru.log")
local ts = require("aru.ts")

-- ============================================================================
-- Configuration
-- ============================================================================

---@type SmartJmp.Config
local default_config = {
    -- Cursor movement is captured after it has been quiet for this long.
    --
    -- Raise this if normal scrolling or repeated motions create too many jump
    -- areas. Lower it if SmartJmp feels slow to notice intentional movement.
    debounce_ms = 250,

    -- Minimum line distance that counts as a meaningful move when Treesitter
    -- cannot identify a semantic area.
    --
    -- This is the non-semantic fallback used for buffers without textobject
    -- queries, unsupported filetypes, or places where no configured capture
    -- contains the cursor. Raise it to capture fewer small movements; lower it
    -- if fallback jump history misses useful locations.
    major_move_lines = 38,

    -- Maximum number of characters used when a Treesitter node has no `name` field.
    --
    -- SmartJmp normally labels semantic areas from a node's `name` field. Some
    -- captures do not expose one, so we fall back to a short snippet from the
    -- node start. Keep this small; it is for logs/debug labels, not display UI.
    max_ts_field_len = 10,

    -- How existing history entries behave when the current settled area matches them.
    --
    -- `stack` preserves chronological prev/next navigation: revisiting B in
    -- [A, B, C] updates B in place and keeps C available as the next target.
    -- `mru` treats revisited areas as most-recently-used and moves them to the end.
    stack_mode = "stack",

    -- Maximum number of semantic jump areas kept per buffer.
    --
    -- Larger values preserve deeper in-file history at the cost of more extmarks
    -- and slightly more state. Smaller values keep the history focused on recent
    -- work and make next/prev cycling easier to reason about.
    max_history = 10,

    -- Number of recent file-history entries checked before adding a new mark.
    --
    -- This keeps deliberate file history from becoming A/B/A/B noise when you
    -- repeatedly inspect the same temporary target. Raise it to deduplicate more
    -- aggressively; lower it if revisiting a file should create a fresh mark
    -- sooner.
    max_file_lookback = 3,

    -- Minimum size required for block.outer captures.
    --
    -- Small blocks are usually local control-flow noise rather than useful jump
    -- destinations. This threshold only affects block.outer; functions, methods,
    -- and classes remain eligible regardless of size.
    min_block_lines = 20,

    -- Textobject captures that SmartJmp treats as semantic areas.
    --
    -- Lower numbers win when multiple configured captures contain the cursor;
    -- ties are resolved by selecting the smaller area. Add captures here to make
    -- more textobjects navigable, remove captures to make history less granular,
    -- or adjust weights to prefer broader/narrower semantic anchors.
    capture_priority = {
        ["function.outer"] = 1,
        ["method.outer"] = 2,
        ["class.outer"] = 3,
    },

    ---@type string[]
    -- Filetypes ignored by both semantic and file history.
    --
    -- Use this for plugin buffers that have normal names but are not meaningful
    -- editing targets, such as pickers, file explorers, dashboards, or scratch
    -- interfaces.
    exclude_filetypes = { "oil", "fzf" },

    -- Buftypes ignored by both semantic and file history.
    --
    -- These buffers are usually transient or controlled by another subsystem.
    -- Tracking them would create dead jump areas or pull temporary UI into the
    -- deliberate file history.
    exclude_buftypes = {
        "help",
        "nofile",
        "quickfix",
        "terminal",
        "prompt",
        "acwrite",
    },

    -- Created during setup. Kept in config so reset/setup share the same group.
    augroup_id = nil,

    -- Namespace used for extmarks that keep jump areas stable across edits.
    namespace = vim.api.nvim_create_namespace("aru_smartjmp"),
}

-- ============================================================================
-- Module State
-- ============================================================================

---@alias SmartJmp.StackMode "stack" | "mru"

---@class SmartJmp.Config
---@field debounce_ms number
---@field major_move_lines number
---@field max_ts_field_len number
---@field stack_mode SmartJmp.StackMode
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
---@field file_mark fun(bufnr?: number)
---@field file_next fun()
---@field file_prev fun()
---@field with_file_mark fun(fn: fun(...): any): fun(...): any
---@field file_toggle fun()
---@field next fun()
---@field prev fun()
---@field reset fun()
---@field setup fun()
local M = {
    f_hist = nil,
    buffers = {},
    suppress_cursor_moved = false,
    config = vim.tbl_extend("force", {}, default_config),
}

-- ============================================================================
-- Generic Helpers
-- ============================================================================

--- Suppress SmartJmp's own restore movement long enough for deferred
--- CursorMoved events from winrestview() to pass without starting a capture.
---
---@param fn fun(): any
---@return any
local function with_suppressed_cursor_moved(fn)
    M.suppress_cursor_moved = true

    local ok, result = xpcall(fn, debug.traceback)

    vim.defer_fn(function() M.suppress_cursor_moved = false end, M.config.debounce_ms + 25)

    if not ok then error(result, 0) end

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

---@param t uv.uv_timer_t?
local function stop_burst(t)
    if t and not t:is_closing() then t:stop() end
end

---@param history SmartJmp.BufferHistory
---@return string
local function history_debug(history)
    local parts = {}

    for i, area in ipairs(history.entries) do
        local semantic = area.semantic
        local label = semantic and (semantic.name or semantic.kind or semantic.capture)
            or "fallback"

        parts[#parts + 1] = ("%s%d:%s@%d:%d%s"):format(
            i == history.index and "*" or "",
            i,
            label or "area",
            area.view.lnum,
            area.view.col,
            area.extmark_id and ("#" .. area.extmark_id) or ""
        )
    end

    return table.concat(parts, " ")
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

-- ============================================================================
-- Semantic Area Detection
-- ============================================================================

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
---@field area SmartJmp.SemanticArea
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

---@alias SmartJmp.TreesitterCapture fun(...): integer?, TSNode?

---@class SmartJmp.TreesitterIterator
---@field iter SmartJmp.TreesitterCapture
---@field query vim.treesitter.Query

---@param bufnr number
---@param view SmartJmp.View
---@return SmartJmp.SemanticArea?
--- Finds the best configured textobject capture containing the saved view.
---
--- Small block.outer captures are ignored to avoid local-control-flow noise.
--- When several captures contain the cursor, capture_priority decides first;
--- ties choose the smaller semantic area.
local function semantic_area_at(bufnr, view)
    ---@type SmartJmp.SemanticCandidate?
    local best_match = nil
    local row = math.max(view.lnum - 1, 0)
    local col = math.max(view.col, 0)

    local iterator = ts.iter_textobj_captures(bufnr)
    if not iterator then return nil end

    for id, node, _, _ in iterator.iter do
        local capture_name = iterator.query.captures[id]

        local weight = M.config.capture_priority[capture_name]
        if not weight then goto continue end

        local name = ts.node_field_text(node, "name", bufnr, M.config.max_ts_field_len)

        local sr, sc, er, ec = node:range()
        local semantic = {
            source = "textobject",
            capture = capture_name,
            kind = node:type(),
            name = name,
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

--- Treat two Treesitter captures as the same practical editing area.
---@param area SmartJmp.SemanticArea
---@param other SmartJmp.SemanticArea
---@return boolean
local function same_semantic_area(area, other)
    if area.capture ~= other.capture then return false end
    if area.kind ~= other.kind then return false end
    if area.name ~= other.name then return false end

    if area.start_row <= other.start_row and other.start_row <= area.end_row then return true end
    if other.start_row <= area.start_row and area.start_row <= other.end_row then return true end

    -- Treesitter ranges can shift after edits; nearby starts still represent
    -- the same practical area for jump-history purposes.
    return math.abs(area.start_row - other.start_row) <= 5
end

---@param view SmartJmp.View
---@param other SmartJmp.View
---@return boolean
local function is_fallback_major_move(view, other)
    return math.abs(view.lnum - other.lnum) > M.config.major_move_lines
end

---@param area SmartJmp.Area
---@param candidate SmartJmp.SemanticArea?
---@param view SmartJmp.View
---@return boolean
local function area_matches_candidate(area, candidate, view)
    if area.semantic and candidate then return same_semantic_area(area.semantic, candidate) end

    if not area.semantic and not candidate then
        return not is_fallback_major_move(area.view, view)
    end

    return false
end

-- ============================================================================
-- Area Construction
-- ============================================================================

---@class SmartJmp.SemanticArea
---@field source "textobject"
---@field name string?
---@field capture string?
---@field kind string
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number

---@class SmartJmp.Area
---@field extmark_id number?
---@field view SmartJmp.View
---@field semantic SmartJmp.SemanticArea?

---@param view SmartJmp.View
---@param semantic SmartJmp.SemanticArea?
---@return SmartJmp.Area
local function area_from_view(view, semantic)
    return {
        extmark_id = nil,
        view = vim.tbl_extend("force", {}, view),
        semantic = semantic,
    }
end

---@param bufnr number
---@param view SmartJmp.View
---@param extmark_id number?
---@return number? extmark_id
local function set_area_extmark(bufnr, view, extmark_id)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local row = math.min(math.max(view.lnum - 1, 0), math.max(line_count - 1, 0))
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
    local col = math.min(math.max(view.col, 0), #line)

    local opts = {
        right_gravity = true,
        end_row = row,
        end_col = math.min(#line, col + 1),
    }
    if extmark_id then opts.id = extmark_id end

    local ok, extmark_id =
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.config.namespace, row, col, opts)
    if not ok then
        log:warn(
            ("set_area_extmark: failed to set extmark for buffer %d (%s)"):format(
                bufnr,
                vim.api.nvim_buf_get_name(bufnr)
            )
        )
        return nil
    end

    return extmark_id
end

---@param bufnr number
---@param extmark_id number
---@return boolean success
local function delete_area_extmark(bufnr, extmark_id)
    if bufnr and extmark_id and vim.api.nvim_buf_is_valid(bufnr) then
        return pcall(vim.api.nvim_buf_del_extmark, bufnr, M.config.namespace, extmark_id)
    end

    return true
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

    -- Prefer an already loaded buffer for this path so restore does not create
    -- duplicate buffers after cached buffer numbers become stale.
    local existing = vim.fn.bufnr(path)
    if existing ~= -1 and vim.api.nvim_buf_is_loaded(existing) then return existing, false end

    -- If the file still exists, load it into this session and use the new buffer.
    local stat = vim.uv.fs_stat(path)
    if not stat or stat.type ~= "file" then
        log:info("restore: invalid file for %s", path)
        return nil, false
    end

    -- Verify loading succeeded before the caller attempts to restore a view.
    local new_bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(new_bufnr)

    if not vim.api.nvim_buf_is_valid(new_bufnr) or not vim.api.nvim_buf_is_loaded(new_bufnr) then
        return nil, false
    end

    return new_bufnr, false
end

-- ============================================================================
-- View Restore
-- ============================================================================

---@param bufnr number
---@param extmark_id number
---@param view SmartJmp.View
---@return boolean ok
---@return boolean extmark_valid
local function load_buffer_view(bufnr, extmark_id, view)
    local extmark_valid = false

    if extmark_id then
        local ok, pos =
            pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, M.config.namespace, extmark_id, {})
        if ok and pos[1] then
            -- Neovim extmarks are 0-indexed, so add one for view line numbers.
            view.lnum = pos[1] + 1
            view.col = pos[2]

            extmark_valid = true
        else
            extmark_valid = false
        end
    end

    local ok = pcall(vim.fn.winrestview, view)
    if not ok then
        log:warn(
            ("restore winrestview failed bufnr=%d extmark=%s view=%d:%d"):format(
                bufnr,
                tostring(extmark_id),
                view.lnum,
                view.col
            )
        )
        return false, extmark_valid
    end

    return true, extmark_valid
end

---@param state SmartJmp.BufferState
---@param area SmartJmp.Area
---@return boolean updated
local function refresh_area_view_from_extmark(state, area)
    if not area.extmark_id then return false end

    local ok, pos = pcall(
        vim.api.nvim_buf_get_extmark_by_id,
        state.bufnr,
        M.config.namespace,
        area.extmark_id,
        {}
    )

    if not ok or type(pos) ~= "table" or not pos[1] then
        area.extmark_id = nil
        return false
    end

    area.view.lnum = pos[1] + 1
    area.view.col = pos[2]

    return true
end

---@param state SmartJmp.BufferState
local function sanitize_history(state)
    for _, area in ipairs(state.history.entries) do
        local updated = refresh_area_view_from_extmark(state, area)
        if updated then
            local semantic = semantic_area_at(state.bufnr, area.view)
            if semantic then area.semantic = semantic end
        end
    end
end

---@param state SmartJmp.BufferState
---@return boolean sanitized
local function maybe_sanitize_history(state)
    local tick = vim.api.nvim_buf_get_changedtick(state.bufnr)
    if tick == state.changetick then return false end

    sanitize_history(state)
    state.changetick = tick

    return true
end

---@param bufnr number
---@param area SmartJmp.Area
---@return boolean restored
---@return SmartJmp.Area?
local function restore_area(bufnr, area)
    local ok, result = pcall(function()
        return with_suppressed_cursor_moved(function()
            local restored, extmark_valid = load_buffer_view(bufnr, area.extmark_id, area.view)
            return {
                restored = restored,
                extmark_valid = extmark_valid,
            }
        end)
    end)

    if not ok or not result.restored then
        local path = vim.api.nvim_buf_get_name(bufnr)
        log:warn(
            ("restore: failed to restore area for %s ok=%s result=%s"):format(
                path,
                tostring(ok),
                vim.inspect(result)
            )
        )
        return false, nil
    end

    if area.extmark_id and not result.extmark_valid then area.extmark_id = nil end

    return true, area
end

---@param bufnr number
---@param delta number
---@param history SmartJmp.BufferHistory
---@return SmartJmp.Area? area
local function move(bufnr, delta, history)
    local target_index, target_area = history:target(delta)
    if not target_index or not target_area then return nil end

    -- Remove only entries that cannot be restored; valid entries keep their order.
    local ok, area = restore_area(bufnr, target_area)
    if not ok then
        history:remove(target_index)

        return nil
    end

    history.index = target_index

    return area
end

-- ============================================================================
-- Buffer-Local Semantic History
-- ============================================================================

---@class SmartJmp.BufferHistory
--- Buffer-local semantic jump history.
---
--- Entries are anchored with extmarks when possible, so edits can move saved
--- jump areas without invalidating them.
---@field index number
---@field entries SmartJmp.Area[]
local BufferHistory = {}
BufferHistory.__index = BufferHistory

---@return SmartJmp.BufferHistory
function BufferHistory:new()
    return setmetatable({
        index = 0,
        entries = {},
    }, BufferHistory)
end

---@return SmartJmp.Area?
function BufferHistory:current() return self.entries[self.index] end

---@param index number
---@return SmartJmp.Area
function BufferHistory:get(index)
    assert(index <= #self.entries)
    return self.entries[index]
end

---@return SmartJmp.Area[] pruned
function BufferHistory:truncate()
    if self.index == #self.entries then return {} end

    local pruned = {}

    -- Remove forward entries from the end so the active index remains stable.
    for i = #self.entries, self.index + 1, -1 do
        table.insert(pruned, table.remove(self.entries, i))
    end

    assert(self.index == #self.entries)

    return pruned
end

---@param index number
---@param patch? table<string, any>
function BufferHistory:reactivate(index, patch)
    if index < 1 or index > #self.entries then
        log:warn("update: invalid index %d for %d entries", index, #self.entries)
        return
    end

    -- Stack mode updates the matched entry in place. MRU mode moves it to the
    -- end, turning local history into a recency list instead of a prev/next stack.
    local target_index = index
    if M.config.stack_mode == "mru" and index < #self.entries then
        local area = table.remove(self.entries, index)
        table.insert(self.entries, area)
        target_index = #self.entries
    end

    self.index = target_index
    self.entries[target_index] = vim.tbl_extend("force", self.entries[target_index], patch or {})
end

---@param semantic SmartJmp.SemanticArea?
---@param view SmartJmp.View
---@return number?
function BufferHistory:find_match(semantic, view)
    for idx, entry in ipairs(self.entries) do
        if entry and area_matches_candidate(entry, semantic, view) then return idx end
    end

    return nil
end

---@param delta number
---@return number?, SmartJmp.Area?
function BufferHistory:target(delta)
    local target_index = self.index + delta

    -- We don't want to move outside the bounds of the history.
    if target_index < 1 or target_index > #self.entries then
        log:trace("move: invalid index %d for %d entries", target_index, #self.entries)
        return nil, nil
    end

    return target_index, self.entries[target_index]
end

---@param target_index number
function BufferHistory:remove(target_index)
    table.remove(self.entries, target_index)

    -- Keep the active index pointing at the same logical position after removal.
    if target_index < self.index then self.index = math.max(0, self.index - 1) end
end

---@param area SmartJmp.Area
function BufferHistory:append(area)
    -- We add the areas to history entries and if we exceed the max history we
    -- prune the oldest entry. This ensures we don't grow unbounded.
    table.insert(self.entries, area)
    self.index = #self.entries
end

---@param area SmartJmp.Area
---@return SmartJmp.Area?
function BufferHistory:append_capped(area)
    self:append(area)
    if #self.entries <= M.config.max_history then return nil end

    local pruned = table.remove(self.entries, 1)
    self.index = #self.entries

    return pruned
end

-- ============================================================================
-- Deliberate File History
-- ============================================================================

--- File history is intentionally explicit. It is not a buffer list.
---
--- Callers mark the current file before an action that may leave the current
--- work area. file_toggle() can then bounce between the marked file and the
--- inspected file without making every visited buffer part of the workspace.

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
        log:trace("add: invalid buffer, %d does not point to a path.", bufnr)
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
        log:info("move: invalid index %d for %d entries", target_index, #self.entries)
        return nil
    end

    local state = self.entries[target_index]

    -- Refresh stale buffer-number caches before focusing the target file. Extmark
    -- ids are memory-bound and are cleared separately when buffers are wiped.
    local bufnr, cache_hit = ensure_buffer_loaded(state.path, state.bufnr)
    if not bufnr then
        log:info("restore: invalid buffer for %s", state.path)

        -- Drop stale paths when encountered; file history should contain only
        -- targets that can be restored.
        table.remove(self.entries, target_index)
        if delta < 0 then self.index = math.max(0, self.index - 1) end

        return nil
    end

    if not cache_hit then state.bufnr = bufnr end

    -- Focus the target buffer if another buffer is currently active.
    if vim.api.nvim_get_current_buf() ~= state.bufnr then
        vim.api.nvim_set_current_buf(state.bufnr)
    end

    vim.defer_fn(function()
        -- Restore the target buffer's active local area, if one exists.
        local buf_state = M.buffers[state.path]
        local area = buf_state.history:current()
        if area then restore_area(buf_state.bufnr, area) end
    end, 10)

    self.index = target_index

    return state
end

-- ============================================================================
-- Buffer State And Autocmd Lifecycle
-- ============================================================================

---@class SmartJmp.BufferState
---@field path string
---@field bufnr number?
---@field changetick number
---@field debounce uv.uv_timer_t?
---@field history SmartJmp.BufferHistory
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
        changetick = vim.api.nvim_buf_get_changedtick(bufnr),
        debounce = timer,
        history = BufferHistory:new(),
    }, BufferState)
end

---@param state SmartJmp.BufferState
---@param view SmartJmp.View
local function record_buffer_area(state, view)
    maybe_sanitize_history(state)

    local semantic = semantic_area_at(state.bufnr, view)

    if #state.history.entries == 0 then
        local area = area_from_view(view, semantic)
        area.extmark_id = set_area_extmark(state.bufnr, view)

        state.history:append(area)
        return
    end

    local index = state.history:find_match(semantic, view)
    if index then
        local area = state.history:get(index)

        state.history:reactivate(index, {
            extmark_id = set_area_extmark(state.bufnr, view, area.extmark_id),
            view = vim.tbl_extend("force", {}, view),
            semantic = semantic,
        })
        return
    end

    if state.history.index < #state.history.entries then
        -- Recording a genuinely new area from the middle creates a new branch,
        -- so forward entries are no longer reachable and their extmarks can go.
        local pruned_areas = state.history:truncate()
        for _, pruned_area in ipairs(pruned_areas) do
            if not delete_area_extmark(state.bufnr, pruned_area.extmark_id) then
                log:warn("truncate: failed to remove extmark for %s", state.path)
            end
        end
    end

    local new_area = area_from_view(view, semantic)
    new_area.extmark_id = set_area_extmark(state.bufnr, view)

    local pruned = state.history:append_capped(new_area)
    if pruned and not delete_area_extmark(state.bufnr, pruned.extmark_id) then
        log:warn(
            ("add: failed to remove extmark_id (%d) in buffer: %s (%d)"):format(
                pruned.extmark_id,
                state.path,
                state.bufnr
            )
        )
    end
end

---@param bufnr number
local function create_cursor_move_autocmd(bufnr)
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = M.config.augroup_id,
        buffer = bufnr,
        desc = "SmartJmp: capture semantic jump after cursor settles",
        callback = function(ev)
            if M.suppress_cursor_moved then return end

            -- Ignore plugin/scratch buffers before starting debounce work.
            if not is_trackable_buffer(ev.buf) then return end

            -- on_buf_enter creates state for every trackable buffer; if it is
            -- missing here, a race or manual autocmd triggered us, so bail.
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
                    -- State can change while debounce waits; re-read it before
                    -- touching timers, buffers, or windows.
                    local state = M.buffers[origin_path]
                    if not state then return end
                    local timer = state.debounce
                    if not timer then return end

                    if state.bufnr ~= origin_buf then
                        if state.path == origin_path then state.bufnr = origin_buf end
                    end

                    -- Ensure we are still in the original window and buffer.
                    -- BufLeave should normally cancel this, but delayed callbacks
                    -- are defensive because window state can change at any time.
                    if
                        not vim.api.nvim_win_is_valid(origin_win)
                        or vim.api.nvim_win_get_buf(origin_win) ~= origin_buf
                        or not is_trackable_buffer(origin_buf)
                    then
                        stop_burst(timer)
                        return
                    end

                    -- capture_view() is window-local; run it in the original window.
                    vim.api.nvim_win_call(
                        origin_win,
                        function() record_buffer_area(state, capture_view()) end
                    )

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
        desc = "SmartJmp: release buffer timer and volatile jump anchors",
        callback = function(ev)
            local state = M.buffers[vim.api.nvim_buf_get_name(ev.buf)]
            if not state then return end

            if state.debounce then
                -- Wiped buffers lose memory-bound anchors; keep durable path/view state.
                stop_burst(state.debounce)
                state.debounce:close()

                state.debounce = nil
                state.bufnr = nil
            end

            -- Keep durable path/view history, but clear memory-bound extmarks.
            for _, area in ipairs(state.history.entries) do
                area.extmark_id = nil
            end
        end,
    })
end

---@param bufnr number
local function create_buf_leave_autocmd(bufnr)
    vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
        group = M.config.augroup_id,
        buffer = bufnr,
        desc = "SmartJmp: cancel pending cursor-move capture",
        callback = function()
            local state = M.buffers[vim.api.nvim_buf_get_name(bufnr)]
            if state then stop_burst(state.debounce) end
        end,
    })
end

---@param bufnr number
local function on_buf_enter(bufnr)
    -- Special buffers should never create semantic areas or file-history marks.
    local path = vim.api.nvim_buf_get_name(bufnr)
    if not is_trackable_buffer(bufnr) then
        log:trace("on_buf_enter: excluded %s", path)
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

        -- Recreate the timer if a previously tracked buffer was wiped and reopened.
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
    local bufnr = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(bufnr)

    -- Moving backward records the inspected file before returning to the mark.
    -- That gives file_toggle() a forward entry to bounce back to.
    if delta < 0 then M.f_hist:add_if_current_differs(bufnr) end

    local trg_state = M.f_hist:move(delta)
    if not trg_state then log:info("move: failed navigation to buffer %s", path) end
end

---@param delta number
local function buffer_move(delta)
    local bufnr = vim.api.nvim_get_current_buf()
    local state = M.buffers[vim.api.nvim_buf_get_name(bufnr)]
    assert(state)

    maybe_sanitize_history(state)

    local ok = move(state.bufnr, delta, state.history)
    if not ok then
        log:trace(
            ("move: failed to move: %s in buffer: %d (%s)"):format(delta, state.bufnr, state.path)
        )
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

---@param bufnr number?
--- Mark a file as a deliberate return point for cross-file inspection.
function M.file_mark(bufnr) M.f_hist:add(bufnr or vim.api.nvim_get_current_buf()) end
function M.file_next() file_move(1) end
function M.file_prev() file_move(-1) end

---@param fn fun(...): any
---@return fun(...): any
--- Wrap an action so the current file is marked before the action runs.
---
--- Intended for LSP/fuzzy actions that may jump outside the current work area.
function M.with_file_mark(fn)
    return function(...)
        M.file_mark(vim.api.nvim_get_current_buf())
        return fn(...)
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

if vim.g.aru_test then
    M._test = {
        history_debug = history_debug,
        record_buffer_area = record_buffer_area,
    }
end

--- Reset all SmartJmp state and restart tracking for the current buffer.
function M.reset()
    log:trace("reset: states for %d buffers", vim.tbl_count(M.buffers))

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

--- Initialize SmartJmp autocmds and tracking for the current buffer.
function M.setup()
    if not M.config.augroup_id then
        M.config.augroup_id = vim.api.nvim_create_augroup("aru_smartjmp", { clear = true })

        vim.api.nvim_create_autocmd("BufEnter", {
            group = M.config.augroup_id,
            desc = "SmartJmp: initialize tracking for entered buffer",
            callback = function(ev) on_buf_enter(ev.buf) end,
        })

        on_buf_enter(vim.api.nvim_get_current_buf())
    end
end

return M
