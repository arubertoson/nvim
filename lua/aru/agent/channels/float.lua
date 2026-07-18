---@module "aru.agent.channels.float"
---Streams agent responses into an anchored read-only floating window with
---page-based history. Each float response is a page; navigate with page_prev/page_next.

local M = {}

local logger = require("aru.log"):bind("agent.channels.float")
local config = require("aru.agent.config")
local constants = require("aru.agent.constants")
local line_acc = require("aru.agent.lines")
local progress = require("aru.agent.progress")
local stream = require("aru.agent.stream")
local ui = require("aru.agent.ui")
local process = require("aru.agent.process")

---@class aru.agent.channels.float.Page
---@field lines string[]
---@field label string

---@class aru.agent.channels.float.State: aru.agent.progress.State
---@field buf integer
---@field win integer
---@field ns integer
---@field augroup integer
---@field pending string
---@field display_pending boolean
---@field display_pending_lines integer
---@field streaming boolean
---@field user_scrolled boolean
---@field title_label string
---@field stream_id integer

local markview_autocmds_ready = false

---@type aru.agent.channels.float.Page[]
local _pages = {}

---@type integer
local _page_index = 0

---@type integer
local _stream_id = 0

---@type aru.agent.channels.float.State|nil
local _state = nil

---@param name "before_open"|"after_close"
local function run_lifecycle_hook(name)
    local hook = config.get().float[name]
    if not hook then return end

    local ok, err = pcall(hook)
    if not ok then logger:error("float %s hook failed: %s", name, err) end
end

---@return table|nil
local function markview_actions()
    if not markview_autocmds_ready then
        local ok, autocmds = pcall(require, "markview.autocmds")
        if not ok then return nil end
        local setup_ok = pcall(autocmds.setup)
        if not setup_ok then return nil end
        markview_autocmds_ready = true
    end

    local ok, actions = pcall(require, "markview.actions")
    if not ok then return nil end
    return actions
end

---@param buf integer
local function attach_markview(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local actions = markview_actions()
    if not actions then return end
    pcall(actions.attach, buf, { enable = true, hybrid_mode = false })
end

---@param buf integer
local function render_markview(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local actions = markview_actions()
    if not actions then return end
    pcall(actions.render, buf, { enable = true, hybrid_mode = false })
end

---@param state aru.agent.channels.float.State
local function stop_spinner(state) progress.stop(state) end

local function close_float()
    if not _state then return end
    local state = _state
    _state = nil
    stop_spinner(state)
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    ui.close_win_buf(state.win, state.buf)
    run_lifecycle_hook("after_close")
end

local function max_height()
    local layout = constants.UI.READ_FLOAT
    local available =
        math.max(1, vim.o.lines - vim.o.cmdheight - layout.ROW - layout.BOTTOM_MARGIN)
    return math.max(1, math.floor(available * layout.HEIGHT_RATIO))
end

---@param buf integer
local function estimated_rows(buf)
    local rows = 0
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        rows = rows
            + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / constants.UI.READ_FLOAT.WIDTH))
    end
    return math.max(1, rows)
end

---@param state aru.agent.channels.float.State
local function content_rows(state)
    if vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_win_text_height then
        local ok, height =
            pcall(vim.api.nvim_win_text_height, state.win, { start_row = 0, end_row = -1 })
        if ok and type(height) == "table" and type(height.all) == "number" then
            return math.max(1, height.all)
        end
    end

    return estimated_rows(state.buf)
end

---@param state aru.agent.channels.float.State
local function anchor_top(state)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
end

---@param state aru.agent.channels.float.State
local function resize(state)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    local new_h = math.min(content_rows(state), max_height())
    local cfg = vim.api.nvim_win_get_config(state.win)
    if cfg.height ~= new_h then vim.api.nvim_win_set_config(state.win, { height = new_h }) end
    if not state.user_scrolled then anchor_top(state) end
end

---@param state aru.agent.channels.float.State
local function title(state)
    local page_info = #_pages > 1 and (" %d/%d"):format(_page_index, #_pages) or ""
    if state.streaming then
        return (" %s%s %s %s "):format(state.title_label, page_info, progress.frame(state), state.phrase)
    end
    return (" %s%s "):format(state.title_label, page_info)
end

---@param state aru.agent.channels.float.State
local function refresh_title(state)
    if vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_set_config(state.win, { title = title(state) })
    end
end

---@param state aru.agent.channels.float.State
local function start_spinner(state)
    progress.start(state, {
        is_current = function() return _state == state end,
        refresh = function() refresh_title(state) end,
    })
end

---@param buf integer
---@param modifiable boolean
local function set_modifiable(buf, modifiable)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    pcall(vim.api.nvim_set_option_value, "modifiable", modifiable, { buf = buf })
end

---@param buf integer
---@param start integer
---@param end_ integer
---@param lines string[]
local function set_lines(buf, start, end_, lines)
    set_modifiable(buf, true)
    pcall(vim.api.nvim_buf_set_lines, buf, start, end_, false, lines)
    set_modifiable(buf, false)
end

---@param state aru.agent.channels.float.State
---@param delta string
local function append(state, delta)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end

    local complete, pending = line_acc.split_pending(state.pending, delta)
    state.pending = pending

    local line_count = vim.api.nvim_buf_line_count(state.buf)
    local replace_start = line_count
    local replace_end = line_count

    if state.display_pending then
        replace_start = math.max(0, line_count - state.display_pending_lines)
        replace_end = line_count
    elseif line_count == 1 and vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] == "" then
        replace_start = 0
        replace_end = 1
    end

    local replacement = complete
    if state.pending ~= "" then
        table.insert(replacement, state.pending)
        state.display_pending = true
        state.display_pending_lines = 1
    else
        state.display_pending = false
        state.display_pending_lines = 0
    end

    if not vim.tbl_isempty(replacement) then
        set_lines(state.buf, replace_start, replace_end, replacement)
        render_markview(state.buf)
    elseif replace_start == 0 and replace_end == 1 then
        set_lines(state.buf, 0, 1, { "" })
        render_markview(state.buf)
    end

    resize(state)
end

---@param state aru.agent.channels.float.State
local function save_current_page(state)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    local page = _pages[_page_index]
    if not page then return end
    page.lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
end

---@param state aru.agent.channels.float.State
local function flush(state)
    stop_spinner(state)
    state.streaming = false
    refresh_title(state)

    if state.pending ~= "" and not state.display_pending then
        local pending = state.pending
        state.pending = ""
        append(state, pending)
    end
    state.pending = ""
    state.display_pending = false
    state.display_pending_lines = 0

    save_current_page(state)
end

---@param state aru.agent.channels.float.State
---@param direction "down"|"up"
local function scroll(state, direction)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    if state.streaming then return end

    local win_height = vim.api.nvim_win_get_height(state.win)
    local amount = vim.v.count > 0 and vim.v.count or math.max(1, math.floor(win_height / 2))
    local key = direction == "down" and "<C-e>" or "<C-y>"
    local scroll_key = vim.api.nvim_replace_termcodes(key, true, false, true)

    vim.api.nvim_win_call(state.win, function()
        vim.cmd("normal! " .. amount .. scroll_key)
        local view = vim.fn.winsaveview()
        state.user_scrolled = view.topline > 1 or (view.skipcol or 0) > 0
    end)
end

---@param state aru.agent.channels.float.State
local function install_keymaps(state)
    for _, mapping in ipairs({
        { lhs = "<C-d>", direction = "down" },
        { lhs = "<C-u>", direction = "up" },
    }) do
        local dir = mapping.direction
        local lhs = mapping.lhs
        for _, mode in ipairs({ "n", "i" }) do
            vim.keymap.set(mode, lhs, function()
                local scroll_fn = function()
                    if _state then scroll(_state, dir) end
                end
                if mode == "i" then
                    vim.schedule(scroll_fn)
                else
                    scroll_fn()
                end
            end, {
                buffer = state.buf,
                silent = true,
                desc = "Scroll float " .. dir,
            })
        end
    end
end

---@param lines string[]
---@param opts { streaming: boolean|nil, runtime_label: string|nil }
---@return aru.agent.channels.float.State
local function create_float_window(lines, opts)
    opts = opts or {}

    local buf = ui.create_scratch_buf({
        filetype = constants.UI.FILETYPE_MARKDOWN,
        modifiable = false,
        lines = lines,
    })

    local layout = constants.UI.READ_FLOAT
    local col = math.max(0, vim.o.columns - layout.WIDTH - layout.RIGHT_MARGIN)
    local height = math.min(estimated_rows(buf), max_height())
    local custom = require("aru.custom")

    run_lifecycle_hook("before_open")
    local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
        relative = "editor",
        row = layout.ROW,
        col = col,
        width = layout.WIDTH,
        height = math.max(1, height),
        style = constants.UI.STYLE_MINIMAL,
        border = custom.border or constants.UI.BORDER_ROUNDED,
        title = (" %s "):format(opts.runtime_label or "agent"),
        title_pos = constants.UI.TITLE_POS_LEFT,
        zindex = layout.ZINDEX,
    })
    if not ok then
        run_lifecycle_hook("after_close")
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        error(win)
    end
    ui.apply_win_options(win, {
        wrap = true,
        linebreak = true,
        breakindent = true,
        smoothscroll = true,
        cursorline = false,
        winhl = "CursorLine:Normal",
        scrolloff = 0,
    })

    local ns = vim.api.nvim_create_namespace(constants.NAMESPACE.READ_FLOAT)
    local augroup = vim.api.nvim_create_augroup(constants.AUGROUP.READ_FLOAT, { clear = true })
    ---@type aru.agent.channels.float.State
    local state = {
        buf = buf,
        win = win,
        ns = ns,
        augroup = augroup,
        pending = "",
        display_pending = false,
        display_pending_lines = 0,
        streaming = opts.streaming == true,
        user_scrolled = false,
        title_label = opts.runtime_label or "agent",
        stream_id = 0,
    }
    progress.init(state)
    _state = state
    vim.api.nvim_create_autocmd("WinClosed", {
        group = augroup,
        pattern = tostring(win),
        callback = function()
            if _state ~= state then return end
            _state = nil
            stop_spinner(state)
            pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
            run_lifecycle_hook("after_close")
        end,
    })
    install_keymaps(state)
    refresh_title(state)
    resize(state)
    if state.streaming then start_spinner(state) end

    local map_opts = { buffer = buf, silent = true, nowait = true }
    vim.keymap.set("n", "q", close_float, map_opts)
    vim.keymap.set("n", "<Esc>", close_float, map_opts)

    attach_markview(buf)
    render_markview(buf)
    resize(state)

    return state
end

---@param index integer
---@param opts { streaming: boolean|nil }|nil
---@return aru.agent.channels.float.State|nil
local function show_page(index, opts)
    opts = opts or {}
    local page = _pages[index]
    if not page then return nil end

    _page_index = index

    local state
    if _state and vim.api.nvim_win_is_valid(_state.win) and vim.api.nvim_buf_is_valid(_state.buf) then
        state = _state
        stop_spinner(state)
        state.pending = ""
        state.display_pending = false
        state.display_pending_lines = 0
        state.streaming = opts.streaming == true
        state.user_scrolled = false
        state.title_label = page.label
        set_lines(state.buf, 0, -1, page.lines)
        render_markview(state.buf)
        refresh_title(state)
        resize(state)
        if state.streaming then start_spinner(state) end
    else
        state = create_float_window(page.lines, {
            streaming = opts.streaming,
            runtime_label = page.label,
        })
    end

    return state
end

---@param transport aru.agent.channels.Transport
---@param _ctx aru.agent.ConfigState|nil
---@return boolean
function M.send(transport, _ctx)
    if _state and _state.streaming then save_current_page(_state) end

    table.insert(_pages, { lines = { "" }, label = transport.label })
    _page_index = #_pages

    _stream_id = _stream_id + 1
    local stream_id = _stream_id

    logger:info("float channel send (page %d):\n%s", _page_index, transport.message)

    local state = show_page(_page_index, { streaming = true })
    if not state then return false end
    state.stream_id = stream_id

    transport.run(transport.message, function(event)
        if _state ~= state or state.stream_id ~= stream_id then return end
        stream.dispatch(event, {
            on_thinking = function()
                if progress.update_phrase(state) then refresh_title(state) end
            end,
            on_text = function(delta)
                append(state, delta)
            end,
        })
    end, function(result)
        if _state ~= state or state.stream_id ~= stream_id then return end
        if result.code ~= 0 then
            local err_line = process.stderr_summary(result)
            logger:error("float channel failed (%d): %s", result.code, err_line)
            append(state, "\n[error: " .. err_line .. "]")
        end
        flush(state)
    end)

    return true
end

---@param delta integer
local function navigate_page(delta)
    if _state and _state.streaming then return end
    local target = _page_index + delta
    if target < 1 or target > #_pages then return end
    show_page(target)
end

function M.page_prev() navigate_page(-1) end

function M.page_next() navigate_page(1) end

function M.restore()
    if #_pages == 0 then
        logger:info("No previous float response to restore")
        return
    end
    show_page(_page_index > 0 and _page_index or #_pages)
end

function M.focus()
    if _state and vim.api.nvim_win_is_valid(_state.win) then
        if vim.api.nvim_get_current_win() == _state.win then
            vim.cmd("wincmd p")
        else
            vim.api.nvim_set_current_win(_state.win)
        end
    else
        M.restore()
    end
end

---@param direction "down"|"up"
function M.scroll(direction)
    if _state then scroll(_state, direction) end
end

function M.close() close_float() end

return M
