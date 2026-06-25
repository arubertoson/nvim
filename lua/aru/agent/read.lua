---@module "aru.agent.read"
---Streams an agent response into an anchored read-only floating window. This
---module owns the read float lifecycle, incremental JSON event handling,
---restoration of the last response, and read-float navigation helpers.

local M = {}

local logger = require("aru.log"):bind("agent")
local constants = require("aru.agent.constants")
local line_acc = require("aru.agent.lines")
local progress = require("aru.agent.progress")
local stream = require("aru.agent.stream")
local ui = require("aru.agent.ui")
local util = require("aru.agent.util")

---Describes the assistant message event emitted by the JSON runtime stream.
---
---Read mode consumes `thinking_delta` for title updates and `text_delta` for
---visible response content. Unknown event types are ignored.
---@class AgentReadAssistantMessageEvent
---@field type "thinking_delta"|"text_delta"
---@field delta string|nil

---Describes a parsed JSON runtime event used by read mode.
---
---Only `message_update` events with an assistant payload affect the float.
---@class AgentReadStreamEvent
---@field type string
---@field assistantMessageEvent AgentReadAssistantMessageEvent|nil

---Configures dependencies supplied by the agent facade for read mode.
---
---Passing dependencies in keeps this module focused on UI and streaming rather
---than global agent configuration.
---@class AgentReadSendOpts
---@field render_payload fun(payload: AgentPayload): string
---@field executable string
---@field runtime_args string[]|nil
---@field runtime_label string|nil

---Tracks the lifecycle and rendered contents of the read float.
---
---`pending` stores an incomplete streamed line. When that partial line is already
---drawn, `display_pending_lines` records how many wrapped rows must be replaced
---by the next chunk. `user_scrolled` prevents new content from forcing the view
---back to the top after manual scrolling.
---@class ReadFloatState: AgentProgressState
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

---@type ReadFloatState|nil
local _read_state = nil

---Last completed response lines, kept so the float can be restored after closing.
---@type string[]|nil
local _last_read_lines = nil

---@type string|nil
local _last_read_label = nil

---Stops and closes the read-float spinner timer.
---@param state ReadFloatState
---@return nil
local function read_float_stop_spinner(state) progress.stop(state) end

---Closes the active read float and releases its Neovim resources.
---@return nil
local function close_read_float()
    if not _read_state then return end
    local state = _read_state
    _read_state = nil
    read_float_stop_spinner(state)
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    ui.close_win_buf(state.win, state.buf)
end

---Computes the maximum read-float height for the current editor dimensions.
---@return integer
local function read_float_max_height()
    local layout = constants.UI.READ_FLOAT
    local available =
        math.max(1, vim.o.lines - vim.o.cmdheight - layout.ROW - layout.BOTTOM_MARGIN)
    return math.max(1, math.floor(available * layout.HEIGHT_RATIO))
end

---Estimates visual rows before the floating window exists.
---@param buf integer
---@return integer
local function read_float_estimated_rows(buf)
    local rows = 0
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        rows = rows
            + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / constants.UI.READ_FLOAT.WIDTH))
    end
    return math.max(1, rows)
end

---Counts rendered rows while preserving a minimum visible height.
---@param state ReadFloatState
---@return integer
local function read_float_content_rows(state)
    if vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_win_text_height then
        local ok, height =
            pcall(vim.api.nvim_win_text_height, state.win, { start_row = 0, end_row = -1 })
        if ok and type(height) == "table" and type(height.all) == "number" then
            return math.max(1, height.all)
        end
    end

    return read_float_estimated_rows(state.buf)
end

---Anchors the read float view to the first line.
---@param state ReadFloatState
---@return nil
local function read_float_anchor_top(state)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
end

---Resizes the read float to fit content within the configured maximum height.
---@param state ReadFloatState
---@return nil
local function read_float_resize(state)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    local new_h = math.min(read_float_content_rows(state), read_float_max_height())
    local cfg = vim.api.nvim_win_get_config(state.win)
    if cfg.height ~= new_h then vim.api.nvim_win_set_config(state.win, { height = new_h }) end
    if not state.user_scrolled then read_float_anchor_top(state) end
end

---Scrolls the read float by count or half-window increments.
---
---A numeric count overrides the default half-window step. The function updates
---`user_scrolled` so later stream resizes preserve the user's position.
---@param state ReadFloatState
---@param direction "down"|"up"
---@return nil
local function read_float_scroll(state, direction)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    if not vim.api.nvim_buf_is_valid(state.buf) then return end

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

---Installs read-float-local scroll keymaps.
---@param state ReadFloatState
---@return nil
local function read_float_install_keymaps(state)
    for _, mapping in ipairs({
        { lhs = "<C-d>", direction = "down" },
        { lhs = "<C-u>", direction = "up" },
    }) do
        local dir = mapping.direction
        local lhs = mapping.lhs
        for _, mode in ipairs({ "n", "i" }) do
            vim.keymap.set(mode, lhs, function()
                local scroll = function()
                    if _read_state then read_float_scroll(_read_state, dir) end
                end
                if mode == "i" then
                    vim.schedule(scroll)
                else
                    scroll()
                end
            end, {
                buffer = state.buf,
                silent = true,
                desc = "Scroll read float " .. dir,
            })
        end
    end
end

---Builds the current read-float title.
---@param state ReadFloatState
---@return string
local function read_float_title(state)
    if not state.streaming then return (" %s "):format(state.title_label) end
    return (" %s %s %s "):format(state.title_label, progress.frame(state), state.phrase)
end

---Refreshes the read-float title when the window is still valid.
---@param state ReadFloatState
---@return nil
local function read_float_refresh_title(state)
    if vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_set_config(state.win, { title = read_float_title(state) })
    end
end

---Starts the read-float spinner timer.
---@param state ReadFloatState
---@return nil
local function read_float_start_spinner(state)
    progress.start(state, {
        is_current = function() return _read_state == state end,
        refresh = function() read_float_refresh_title(state) end,
    })
end

---Toggles read-float buffer modifiability for controlled API writes.
---@param buf integer
---@param modifiable boolean
---@return nil
local function read_float_set_modifiable(buf, modifiable)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    pcall(vim.api.nvim_set_option_value, "modifiable", modifiable, { buf = buf })
end

---Writes read-float lines while leaving the buffer read-only afterwards.
---@param buf integer
---@param start integer
---@param end_ integer
---@param lines string[]
---@return nil
local function read_float_set_lines(buf, start, end_, lines)
    read_float_set_modifiable(buf, true)
    pcall(vim.api.nvim_buf_set_lines, buf, start, end_, false, lines)
    read_float_set_modifiable(buf, false)
end

---Appends streamed text to the read float, preserving partial-line state.
---
---Complete newline-delimited text is committed immediately. The incomplete tail
---is wrapped and redrawn in place until a future chunk completes it.
---@param state ReadFloatState
---@param delta string
---@return nil
local function read_float_append(state, delta)
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
        read_float_set_lines(state.buf, replace_start, replace_end, replacement)
        ui.render_markview(state.buf)
    elseif replace_start == 0 and replace_end == 1 then
        read_float_set_lines(state.buf, 0, 1, { "" })
        ui.render_markview(state.buf)
    end

    read_float_resize(state)
end

---Finalizes a read stream and snapshots completed content for restoration.
---@param state ReadFloatState
---@return nil
local function read_float_flush(state)
    read_float_stop_spinner(state)
    state.streaming = false
    read_float_refresh_title(state)

    if state.pending ~= "" and not state.display_pending then
        local pending = state.pending
        state.pending = ""
        read_float_append(state, pending)
    end
    state.pending = ""
    state.display_pending = false
    state.display_pending_lines = 0

    -- Preserve completed content because closing the float deletes its scratch buffer.
    if vim.api.nvim_buf_is_valid(state.buf) then
        _last_read_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
        _last_read_label = state.title_label
    end
end

---Handles one parsed runtime event for the read float.
---@param state ReadFloatState
---@param event AgentReadStreamEvent
---@return nil
local function read_float_handle_event(state, event)
    if event.type ~= constants.EVENT.MESSAGE_UPDATE then return end
    local ev = event.assistantMessageEvent
    if not ev then return end

    if ev.type == constants.EVENT.THINKING_DELTA and type(ev.delta) == "string" then
        if progress.update_phrase(state) then read_float_refresh_title(state) end
        return
    end

    if ev.type == constants.EVENT.TEXT_DELTA and type(ev.delta) == "string" then
        read_float_append(state, ev.delta)
    end
end

---Opens a read float pre-populated with lines.
---@param lines string[]
---@param opts { streaming: boolean|nil, runtime_label: string|nil }
---@return ReadFloatState
local function open_read_float_with_lines(lines, opts)
    opts = opts or {}
    close_read_float()

    local buf = ui.create_scratch_buf({
        filetype = constants.UI.FILETYPE_MARKDOWN,
        modifiable = false,
        lines = lines,
    })

    local layout = constants.UI.READ_FLOAT
    local col = math.max(0, vim.o.columns - layout.WIDTH - layout.RIGHT_MARGIN)
    local height = math.min(read_float_estimated_rows(buf), read_float_max_height())
    local custom = require("aru.custom")
    local win = vim.api.nvim_open_win(buf, false, {
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
    ---@type ReadFloatState
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
    }
    progress.init(state)
    _read_state = state
    read_float_install_keymaps(state)
    read_float_refresh_title(state)
    read_float_resize(state)
    if state.streaming then read_float_start_spinner(state) end

    local map_opts = { buffer = buf, silent = true, nowait = true }
    vim.keymap.set("n", "q", close_read_float, map_opts)
    vim.keymap.set("n", "<Esc>", close_read_float, map_opts)

    ui.attach_markview(buf)
    ui.render_markview(buf)
    read_float_resize(state)

    return state
end

---Opens the read float and streams runtime JSON output into it.
---
---Starts the configured executable in JSON print mode with tools and sessions
---disabled. Runtime stderr is logged and shown in the float when the process
---exits unsuccessfully.
---@param payload AgentPayload
---@param opts AgentReadSendOpts
---@return boolean
---Example:
---```lua
---require("aru.agent").send({ destination = "read", prompt = "Explain this" })
---```
function M.send(payload, opts)
    close_read_float()

    local message = opts.render_payload(payload)
    local executable = opts.executable
    logger:info("send_read (streaming float):\n%s", message)

    local state = open_read_float_with_lines({ "" }, {
        streaming = true,
        runtime_label = opts.runtime_label,
    })

    stream.run_json({
        executable = executable,
        args = opts.runtime_args,
        stdin = message,
        on_event = function(event)
            if _read_state == state then read_float_handle_event(state, event) end
        end,
        on_exit = function(result)
            if _read_state ~= state then return end
            if result.code ~= 0 then
                local err_line = util.stderr_summary(result)
                logger:error("send_read failed (%d): %s", result.code, err_line)
                read_float_append(state, "\n[error: " .. err_line .. "]")
            end
            read_float_flush(state)
        end,
    })

    return true
end

---Restores the last completed read response in a new float.
---@return nil
function M.restore()
    if not _last_read_lines then
        logger:info("No previous read response to restore")
        return
    end
    open_read_float_with_lines(_last_read_lines, { runtime_label = _last_read_label })
end

---Focuses the read float, restores it when closed, or jumps back when already focused.
---@return nil
function M.focus()
    if _read_state and vim.api.nvim_win_is_valid(_read_state.win) then
        if vim.api.nvim_get_current_win() == _read_state.win then
            vim.cmd("wincmd p")
        else
            vim.api.nvim_set_current_win(_read_state.win)
        end
    else
        M.restore()
    end
end

---Scrolls the active read float from any current window.
---@param direction "down"|"up"
---@return nil
function M.scroll(direction)
    if _read_state then read_float_scroll(_read_state, direction) end
end

---Closes the active read float.
---@return nil
function M.close() close_read_float() end

return M
