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
    debounce_ms = 500,
    major_move_lines = 7,

    max_history = 100,

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
    augroup_id = vim.api.nvim_create_augroup("aru_smartjmp", { clear = true }),
    namespace = vim.api.nvim_create_namespace("aru_smartjmp"),
}

---@class SmartJmp.BufferState
---@field path string
---@field bufnr number?
---@field debounce uv.uv_timer_t

---@class SmartJmp.Module
---@field private history SmartJmp.History?
---@field private buffers table<string, SmartJmp.BufferState>
---@field private current_area SmartJmp.Area?
---@field private suppress_cursor_moved boolean
---@field private config SmartJmp.Config
local M = {
    history = nil,
    buffers = {},
    current_area = nil,
    suppress_cursor_moved = false,
    config = vim.tbl_extend("force", {}, default_config),
}

---@class SmartJmp.Config
---@field debounce_ms number
---@field major_move_lines number
---@field max_history number
---@field exclude_filetypes string[]
---@field exclude_buftypes string[]
---@field augroup_id number
---@field namespace  number

---@class SmartJmp.JumpPoint :   vim.fn.winrestview.dict
---@field path  string
---@field bufnr number?
---@field view  SmartJmp.View
---@field extmark_id number?

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

---@param fn fun(): any
---@return any
local function with_suppressed_cursor_moved(fn)
    M.suppress_cursor_moved = true

    local ok, result = pcall(fn)

    M.suppress_cursor_moved = false

    if not ok then error(result) end

    return result
end

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

---@param bufnr number
---@param view SmartJmp.View
---@return SmartJmp.Area
local function area_from_view(bufnr, view)
    return {
        path = vim.api.nvim_buf_get_name(bufnr),
        bufnr = bufnr,
        view = vim.tbl_extend("force", {}, view),
        latest_view = vim.tbl_extend("force", {}, view),
    }
end

---@param area SmartJmp.Area
---@param source string
---@return SmartJmp.JumpPoint
local function jump_point_from_area(area, source)
    return {
        path = area.path,
        bufnr = area.bufnr,
        view = vim.tbl_extend("force", {}, area.view),
        source = source,
    }
end

---@class SmartJmp.Area
---@field path string
---@field bufnr number?
---@field view SmartJmp.View
---@field latest_view SmartJmp.View

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
    }, BufferState)
end

---@class SmartJmp.History
---@field entries SmartJmp.JumpPoint[]
---@field index number
---@field add fun(self: SmartJmp.History, point: SmartJmp.JumpPoint)
---@field move fun(self: SmartJmp.History, delta: number)

local History = {}
History.__index = History

---@return SmartJmp.History
function History:new()
    return setmetatable({
        entries = {},
        index = 0,
    }, History)
end

M.history = History:new()

---@param point SmartJmp.JumpPoint
function History:add(point)
    self:truncate()

    if not point.bufnr or not is_trackable_buffer(point.bufnr) then
        log:warn(("add: invalid buffer for %s"):format(point.path))
        return
    end

    local view = point.view

    -- Naive check if we already have this view in history.
    local last = self.entries[#self.entries]
    if last and last.path == point.path and not is_major_move(last.view, point.view) then
        if last.bufnr and last.extmark_id and vim.api.nvim_buf_is_valid(last.bufnr) then
            pcall(vim.api.nvim_buf_del_extmark, last.bufnr, M.config.namespace, last.extmark_id)
        end

        self.entries[#self.entries] = nil
    end

    local line_count = vim.api.nvim_buf_line_count(point.bufnr)
    local row = math.min(math.max(view.lnum - 1, 0), math.max(line_count - 1, 0))
    local line = vim.api.nvim_buf_get_lines(point.bufnr, row, row + 1, false)[1] or ""
    local col = math.min(math.max(view.col, 0), #line)

    point.extmark_id = vim.api.nvim_buf_set_extmark(point.bufnr, M.config.namespace, row, col, {
        right_gravity = true,
        end_row = row,
        end_col = math.min(#line, col + 1),
    })

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

---@param path string
---@param bufnr number?
---@return number?
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

---@param point SmartJmp.JumpPoint
---@return boolean restored
function History:restore(point)
    -- this will fail if the buffer doesn't exist or isn't loaded
    if not point or not point.view then
        log:warn("restore: invalid point / buffer")
        return false
    end

    -- After we've ensured that the point has a valid buffer we need to update
    -- any point that has invalidated cache. If a invalid cache is found extmark_ids
    -- needs to be cleared as they are memory bound and unusable after a reload.
    local bufnr, buf_cache_valid = ensure_buffer_loaded(point.path, point.bufnr)
    if not bufnr then
        log:warn(("restore: invalid buffer for %s"):format(point.path))
        return false
    end

    -- update the point to reflect whatever buffer we've just loaded, if the buffer
    -- is the same or changed doesn't really matter, we just update it regardless.
    point.bufnr = bufnr
    if not buf_cache_valid then point.extmark_id = nil end

    -- Finally we have to focus the buffer in case it's not the current buffer.
    if vim.api.nvim_get_current_buf() ~= point.bufnr then
        vim.api.nvim_set_current_buf(point.bufnr)
    end

    local extmark_valid = with_suppressed_cursor_moved(function()
        if vim.api.nvim_get_current_buf() ~= point.bufnr then
            vim.api.nvim_set_current_buf(point.bufnr)
        end

        return load_buffer_view(point)
    end)
    if point.extmark_id and not extmark_valid then point.extmark_id = nil end

    M.current_area = area_from_view(point.bufnr, point.view)

    return true
end

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

---@param delta number
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

        return
    end

    -- Only update the index if we've successfully restored the point, otherwise
    self.index = target_index
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

            -- First thing is the setup, we need to ensure that we create a new
            -- buffer state for the current buffer, if we have one already we
            -- should just update it, if necessary.
            local state = M.buffers[vim.api.nvim_buf_get_name(ev.buf)]
            if not state then return end

            local origin_buf = ev.buf
            local origin_win = vim.api.nvim_get_current_win()
            local origin_path = vim.api.nvim_buf_get_name(origin_buf)

            local timer = state.debounce
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
                    -- defeinsive but better safe than sorry.
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
                        if not M.current_area then
                            M.current_area = area_from_view(origin_buf, current)
                            return
                        end

                        if
                            M.current_area.path ~= origin_path
                            or is_major_move(M.current_area.view, current)
                        then
                            local old = assert(M.current_area)
                            M.current_area = area_from_view(origin_buf, current)

                            M.history:add(jump_point_from_area(old, "area-left"))
                        else
                            M.current_area.latest_view = current
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
            if state and state.debounce then
                -- We stop the timer but keep the reference alive if we need to
                -- reactivate it, which will happen in `on_buf_enter`.
                stop_burst(state.debounce)
                state.bufnr = nil
            end

            -- We also need to clean up the history points, not remove them but
            -- ensure that information that will change when we reload the buffer
            -- is cleared.
            for _, point in ipairs(M.history.entries) do
                if point.bufnr == ev.buf then
                    point.bufnr = nil
                    point.extmark_id = nil
                end
            end

            if M.current_area and M.current_area.bufnr == ev.buf then
                M.current_area.bufnr = nil
            end
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

function M.next() M.history:move(1) end

function M.prev() M.history:move(-1) end

function M.reset()
    log:trace(("reset: states for %d buffers"):format(vim.tbl_count(M.buffers)))

    M.history = History:new()
    M.current_area = nil

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

    on_buf_enter(vim.api.nvim_get_current_buf())
end

function M.setup()
    vim.api.nvim_create_autocmd("BufEnter", {
        group = M.config.augroup_id,
        desc = "",
        callback = function(ev) on_buf_enter(ev.buf) end,
    })
end

return M
