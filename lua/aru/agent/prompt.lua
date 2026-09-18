---@module "aru.agent.prompt"
---Opens and manages the floating prompt used to submit agent requests. This
---module owns prompt layout, footer rendering, keymaps, lifecycle cleanup, and
---submission callbacks supplied by the facade.

local M = {}

local constants = require("aru.agent.constants")
local channels = require("aru.agent.channels")
local collect = require("aru.agent.collect")
local session = require("aru.agent.session")
local ui = require("aru.agent.ui")

---@class aru.agent.prompt.Deps
---@field send fun(request: aru.agent.Request): boolean
---@field collect aru.agent.collect.Type[]|nil
---@field cwd string

local PROMPT_LAYOUT = constants.UI.PROMPT
local PROMPT_MIN_ROWS = PROMPT_LAYOUT.MIN_ROWS
local PROMPT_MAX_ROWS = PROMPT_LAYOUT.MAX_ROWS
local PROMPT_LEFT_PADDING = PROMPT_LAYOUT.LEFT_PADDING
local PLACEHOLDER_TEXT = "<user types here>"
local PROMPT_NEWLINE_KEY = "<M-CR>"
local PROMPT_CLOSE_KEY = "<Esc>"

local BLOCK_COLLECT = { collect.COLLECT.BLOCK }

---@class aru.agent.prompt.State
---@field buf integer
---@field win integer
---@field footer_ns integer
---@field augroup integer
---@field send fun(request: aru.agent.Request): boolean
---@field collect aru.agent.collect.Type[]
---@field cwd string

---@type aru.agent.prompt.State|nil
local _prompt_state = nil

---@param state aru.agent.prompt.State
---@return string
local function footer_line(state)
    local continuable, session_index = session.can_continue(state.cwd)
    if continuable then
        return ("[CR] continue S%d   [^CR] new session   [^G] generate   [^P] session"):format(
            session_index
        )
    end

    return "[CR] read   [^CR] new session   [^G] generate   [^P] session"
end

local function prompt_width()
    return math.min(PROMPT_LAYOUT.WIDTH, vim.o.columns - PROMPT_LAYOUT.BORDER_ROWS)
end

---@param buf integer
---@param width integer
local function prompt_content_rows(buf, width)
    local text_width = width - PROMPT_LEFT_PADDING
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local rows = 0
    for _, line in ipairs(lines) do
        local line_width = vim.fn.strdisplaywidth(line)
        rows = rows + math.max(1, math.ceil((line_width + 1) / text_width))
    end
    return math.max(1, math.min(rows, PROMPT_MAX_ROWS))
end

---@param buf integer
local function prompt_win_config(buf)
    local custom = require("aru.custom")
    local width = prompt_width()
    local content_rows = prompt_content_rows(buf, width)
    local height = math.max(PROMPT_MIN_ROWS, content_rows) + 2
    local available_lines = vim.o.lines - vim.o.cmdheight
    return {
        relative = "editor",
        row = math.max(0, math.floor((available_lines - height - PROMPT_LAYOUT.BORDER_ROWS) / 2)),
        col = math.max(0, math.floor((vim.o.columns - width - PROMPT_LAYOUT.BORDER_ROWS) / 2)),
        width = width,
        height = height,
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

    local width = prompt_width()
    local content_rows = prompt_content_rows(buf, width)
    local virt_lines = {}
    local spacer_rows = math.max(1, PROMPT_MIN_ROWS - content_rows + 1)
    for _ = 1, spacer_rows do
        virt_lines[#virt_lines + 1] = { { "", "Normal" } }
    end

    local line = footer_line(state)
    local padding = math.max(0, width - PROMPT_LEFT_PADDING - vim.fn.strdisplaywidth(line))
    virt_lines[#virt_lines + 1] = {
        { string.rep(" ", padding) .. line, constants.UI.HIGHLIGHT_COMMENT },
    }

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
    local cfg = prompt_win_config(state.buf)
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
---@param force_new_session boolean|nil
local function submit_prompt(destination, force_new_session)
    if not _prompt_state then return end
    local state = _prompt_state

    local prompt_text = read_prompt_text(state.buf)
    local send = state.send

    close_prompt()

    if prompt_text == "" then return end

    send({
        destination = destination,
        force_new_session = force_new_session,
        collect = state.collect,
        prompt = prompt_text,
    })
end

local function submit_float_read() submit_prompt(channels.DESTINATION.FLOAT, false) end

local function submit_float_new_session() submit_prompt(channels.DESTINATION.FLOAT, true) end

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

---@param invocation_buf integer
---@return integer[]
local function completion_bufnrs(invocation_buf)
    local bufnrs = {}
    local included = {}

    for _, item in ipairs(require("aru.nav.active").items()) do
        if vim.uv.fs_stat(item.path) then
            local bufnr = item.bufnr
            if not bufnr then bufnr = vim.fn.bufadd(item.path) end
            if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end

            bufnrs[#bufnrs + 1] = bufnr
            included[bufnr] = true
        end
    end

    if require("aru.buf").is_normal_file(invocation_buf) and not included[invocation_buf] then
        bufnrs[#bufnrs + 1] = invocation_buf
    end
    return bufnrs
end

---@param deps aru.agent.prompt.Deps
function M.open(deps)
    if _prompt_state then
        if vim.api.nvim_win_is_valid(_prompt_state.win) then
            pcall(vim.api.nvim_set_current_win, _prompt_state.win)
            return
        end
        close_prompt()
    end

    local invocation_buf = vim.api.nvim_get_current_buf()
    local completion_cwd = vim.fn.getcwd()
    local completion_buffers = completion_bufnrs(invocation_buf)
    local buf = ui.create_scratch_buf({
        filetype = constants.UI.FILETYPE_PROMPT,
        lines = { "" },
    })
    vim.bo[buf].syntax = constants.UI.FILETYPE_MARKDOWN
    vim.b[buf].aru_agent_prompt = true
    vim.b[buf].aru_completion_cwd = completion_cwd
    vim.b[buf].aru_completion_bufnrs = completion_buffers

    local win = vim.api.nvim_open_win(buf, true, prompt_win_config(buf))
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
        send = deps.send,
        collect = deps.collect or BLOCK_COLLECT,
        cwd = deps.cwd,
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
    -- Many terminals encode Ctrl-Enter as Ctrl-J instead of a distinct key.
    vim.keymap.set({ "n", "i" }, "<C-j>", submit_float_new_session, map_opts)
    vim.keymap.set(
        { "n", "i" },
        "<C-g>",
        function() submit_prompt(channels.DESTINATION.EDITOR, nil) end,
        map_opts
    )
    vim.keymap.set(
        { "n", "i" },
        "<C-p>",
        function() submit_prompt(channels.DESTINATION.TMUX, nil) end,
        map_opts
    )
    vim.keymap.set({ "n", "i" }, PROMPT_NEWLINE_KEY, insert_prompt_newline, map_opts)
    vim.keymap.set({ "n", "i" }, PROMPT_CLOSE_KEY, close_prompt, map_opts)

    vim.cmd("startinsert")
end

return M
