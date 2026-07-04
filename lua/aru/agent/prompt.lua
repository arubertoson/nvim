---@module "aru.agent.prompt"
---Opens and manages the floating prompt used to submit agent requests. This
---module owns prompt layout, footer rendering, keymaps, lifecycle cleanup, and
---submission callbacks supplied by the facade.

local M = {}

local constants = require("aru.agent.constants")
local channels = require("aru.agent.channels")
local collect = require("aru.agent.collect")
local runtime = require("aru.agent.runtime")
local session = require("aru.agent.session")
local ui = require("aru.agent.ui")

---@class aru.agent.prompt.OpenOpts
---@field prefer_continue boolean|nil

---@class aru.agent.prompt.Deps
---@field send fun(request: aru.agent.Request): boolean

local PROMPT_LAYOUT = constants.UI.PROMPT
local PROMPT_MAX_ROWS = PROMPT_LAYOUT.MAX_ROWS
local PROMPT_WIDTH = PROMPT_LAYOUT.WIDTH
local PROMPT_LEFT_PADDING = PROMPT_LAYOUT.LEFT_PADDING
local PROMPT_TEXT_WIDTH = PROMPT_WIDTH - PROMPT_LEFT_PADDING
---@return integer
local function footer_decoration_rows()
    return #footer_lines() + 1
end
local PLACEHOLDER_TEXT = "<user types here>"
local PROMPT_NEWLINE_KEY = "<C-j>"
local PROMPT_CLOSE_KEY = "<Esc>"

local BLOCK_COLLECT = { collect.COLLECT.BLOCK }

---@class aru.agent.prompt.State
---@field buf integer
---@field win integer
---@field footer_ns integer
---@field augroup integer
---@field anchor_row integer
---@field anchor_col integer
---@field send fun(request: aru.agent.Request): boolean

---@type aru.agent.prompt.State|nil
local _prompt_state = nil

---@return string[]
local function footer_lines()
    if session.can_continue() then
        return {
            "[CR] continue   [^CR] new session",
            "[^G] generate    [^P] session",
        }
    end

    return {
        "[CR] read        [^G] generate",
        "[^P] session",
    }
end

---@param buf integer
local function prompt_content_rows(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local rows = 0
    for _, line in ipairs(lines) do
        local width = vim.fn.strdisplaywidth(line)
        rows = rows + math.max(1, math.ceil((width + 1) / PROMPT_TEXT_WIDTH))
    end
    return math.max(1, math.min(rows, PROMPT_MAX_ROWS))
end

local function prompt_anchor()
    local decoration_rows = footer_decoration_rows()
    local float_h = PROMPT_MAX_ROWS + decoration_rows + PROMPT_LAYOUT.BORDER_ROWS
    local screen_row = vim.fn.screenrow()
    local screen_lines = vim.o.lines - vim.o.cmdheight
    local row
    if screen_row + float_h + PROMPT_LAYOUT.BELOW_CURSOR_MARGIN <= screen_lines then
        row = screen_row
    else
        row = screen_row - float_h - PROMPT_LAYOUT.ABOVE_CURSOR_MARGIN
    end
    row = math.max(0, row)

    local screen_col = vim.fn.screencol() - 1
    local col = math.min(screen_col, vim.o.columns - PROMPT_WIDTH - PROMPT_LAYOUT.RIGHT_MARGIN)
    col = math.max(0, col)

    return row, col
end

---@param buf integer
---@param anchor_row integer
---@param anchor_col integer
local function prompt_win_config(buf, anchor_row, anchor_col)
    local custom = require("aru.custom")
    local rows = prompt_content_rows(buf)
    return {
        relative = "editor",
        row = anchor_row,
        col = anchor_col,
        width = PROMPT_WIDTH,
        height = rows + footer_decoration_rows(),
        style = constants.UI.STYLE_MINIMAL,
        border = custom.border or constants.UI.BORDER_ROUNDED,
        title = " prompt ",
        title_pos = constants.UI.TITLE_POS_LEFT,
        zindex = PROMPT_LAYOUT.ZINDEX,
    }
end

---@param state aru.agent.prompt.State
local function render_footer(state)
    local buf = state.buf
    local total = vim.api.nvim_buf_line_count(buf)
    local footer_idx = total - 1
    local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    local show_placeholder = total == 1 and first_line == ""

    local lines = footer_lines()
    local virt_lines = { { { "", "Normal" } } }
    for i, line in ipairs(lines) do
        local padding = math.max(0, PROMPT_TEXT_WIDTH - vim.fn.strdisplaywidth(line))
        virt_lines[#virt_lines + 1] = {
            { string.rep(" ", padding) .. line, constants.UI.HIGHLIGHT_COMMENT },
        }
    end

    local opts = {
        virt_lines = virt_lines,
        virt_lines_above = false,
    }

    if show_placeholder then
        opts.virt_text = { { PLACEHOLDER_TEXT, constants.UI.HIGHLIGHT_COMMENT } }
        opts.virt_text_pos = "overlay"
    end

    vim.api.nvim_buf_clear_namespace(buf, state.footer_ns, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, state.footer_ns, footer_idx, 0, opts)
end

---@param state aru.agent.prompt.State
local function resize_prompt(state)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    local cfg = prompt_win_config(state.buf, state.anchor_row, state.anchor_col)
    vim.api.nvim_win_set_config(state.win, cfg)
    render_footer(state)
end

local function close_prompt()
    if not _prompt_state then return end
    local state = _prompt_state
    _prompt_state = nil

    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    ui.close_win_buf(state.win, state.buf)
    vim.cmd("stopinsert")
end

---@param buf integer
local function read_prompt_text(buf)
    local content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(content_lines, "\n")
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

---@param destination aru.agent.channels.Destination
---@param mode aru.agent.runtime.Mode
local function submit_prompt(destination, mode)
    if not _prompt_state then return end
    local state = _prompt_state

    local prompt_text = read_prompt_text(state.buf)
    local send = state.send

    close_prompt()

    if prompt_text == "" then return end

    send({
        destination = destination,
        mode = mode,
        collect = BLOCK_COLLECT,
        prompt = prompt_text,
    })
end

local function submit_float_read()
    local mode = session.can_continue() and runtime.MODE.CONTINUE or runtime.MODE.NEW_SESSION
    submit_prompt(channels.DESTINATION.FLOAT, mode)
end

local function submit_float_new_session()
    submit_prompt(channels.DESTINATION.FLOAT, runtime.MODE.NEW_SESSION)
end

local function insert_prompt_newline()
    if not _prompt_state then return end

    local state = _prompt_state
    local buf = state.buf
    local win = state.win
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then return end

    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = cursor[1]
    local col = cursor[2]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""

    vim.api.nvim_buf_set_lines(buf, row - 1, row, false, {
        line:sub(1, col),
        line:sub(col + 1),
    })
    vim.api.nvim_win_set_cursor(win, { row + 1, 0 })
    resize_prompt(state)
end

---@param opts aru.agent.prompt.OpenOpts|nil
---@param deps aru.agent.prompt.Deps
function M.open(opts, deps)
    opts = opts or {}

    if _prompt_state then
        if vim.api.nvim_win_is_valid(_prompt_state.win) then
            pcall(vim.api.nvim_set_current_win, _prompt_state.win)
            return
        end
        close_prompt()
    end

    local buf = ui.create_scratch_buf({
        filetype = constants.UI.FILETYPE_MARKDOWN,
        lines = { "" },
    })

    local anchor_row, anchor_col = prompt_anchor()
    local win = vim.api.nvim_open_win(buf, true, prompt_win_config(buf, anchor_row, anchor_col))
    ui.apply_win_options(win, {
        wrap = true,
        linebreak = true,
        cursorline = false,
        foldcolumn = tostring(PROMPT_LEFT_PADDING),
        foldenable = false,
    })

    vim.api.nvim_win_set_cursor(win, { 1, 0 })

    local footer_ns = vim.api.nvim_create_namespace(constants.NAMESPACE.PROMPT_FOOTER)
    local augroup = vim.api.nvim_create_augroup(constants.AUGROUP.PROMPT, { clear = true })

    ---@type aru.agent.prompt.State
    local state = {
        buf = buf,
        win = win,
        footer_ns = footer_ns,
        augroup = augroup,
        anchor_row = anchor_row,
        anchor_col = anchor_col,
        send = deps.send,
    }
    _prompt_state = state

    render_footer(state)

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = augroup,
        buffer = buf,
        callback = function() resize_prompt(state) end,
    })

    vim.api.nvim_create_autocmd("WinLeave", {
        group = augroup,
        buffer = buf,
        callback = close_prompt,
    })

    local map_opts = { buffer = buf, silent = true, nowait = true }
    vim.keymap.set({ "n", "i" }, "<CR>", submit_float_read, map_opts)
    vim.keymap.set({ "n", "i" }, "<C-CR>", submit_float_new_session, map_opts)
    vim.keymap.set({ "n", "i" }, "<C-g>", function()
        submit_prompt(channels.DESTINATION.EDITOR, runtime.MODE.ONE_SHOT)
    end, map_opts)
    vim.keymap.set({ "n", "i" }, "<C-p>", function()
        submit_prompt(channels.DESTINATION.TMUX, runtime.MODE.PASTE)
    end, map_opts)
    vim.keymap.set({ "n", "i" }, PROMPT_NEWLINE_KEY, insert_prompt_newline, map_opts)
    vim.keymap.set({ "n", "i" }, PROMPT_CLOSE_KEY, close_prompt, map_opts)

    vim.cmd("startinsert")
end

return M
