---@module "aru.agent.prompt"
---Opens and manages the floating prompt used to submit agent requests. This
---module owns prompt layout, footer rendering, keymaps, lifecycle cleanup, and
---submission callbacks supplied by the facade.

local M = {}

local constants = require("aru.agent.constants")
local ui = require("aru.agent.ui")
local util = require("aru.agent.util")

---Configures prompt opening behavior.
---
---`surrounding_lines` controls fallback context collection when no valid visual
---selection is available.
---@class AgentPromptOpenOpts
---@field surrounding_lines integer|nil

---Provides callbacks required by the prompt without depending on the facade.
---
---Keeping these as dependencies avoids a circular require between the facade and
---the prompt implementation.
---@class AgentPromptDeps
---@field collect_context fun(surrounding_lines: integer|nil): AgentContextItem[]
---@field send fun(request: AgentRequest): boolean

local PROMPT_LAYOUT = constants.UI.PROMPT
local PROMPT_MAX_ROWS = PROMPT_LAYOUT.MAX_ROWS
local PROMPT_WIDTH = PROMPT_LAYOUT.WIDTH
local PROMPT_LEFT_PADDING = PROMPT_LAYOUT.LEFT_PADDING
local PROMPT_TEXT_WIDTH = PROMPT_WIDTH - PROMPT_LEFT_PADDING
local PROMPT_DECORATION_ROWS = PROMPT_LAYOUT.DECORATION_ROWS
local PLACEHOLDER_TEXT = "<user types here>"
local FOOTER_TEXT = "[CR] read   [^G] generate   [^P] session"
local PROMPT_KEYMAPS = {
    { modes = { "n", "i" }, lhs = "<CR>", destination = constants.DESTINATION.READ },
    { modes = { "n", "i" }, lhs = "<C-g>", destination = constants.DESTINATION.GENERATE },
    { modes = { "n", "i" }, lhs = "<C-p>", destination = constants.DESTINATION.SESSION },
}
local PROMPT_NEWLINE_KEY = "<C-j>"
local PROMPT_CLOSE_KEY = "<Esc>"

---Tracks the lifecycle and layout of the floating prompt.
---
---The anchor position is captured once when opening the prompt. Resizes reuse the
---stored anchor so typing does not make the float drift with cursor movement.
---@class PromptState
---@field buf integer
---@field win integer
---@field footer_ns integer
---@field context AgentContextItem[]
---@field augroup integer
---@field anchor_row integer
---@field anchor_col integer
---@field send fun(request: AgentRequest): boolean

---@type PromptState|nil
local _prompt_state = nil

---Computes the prompt content height for wrapped prompt text.
---@param buf integer
---@return integer
local function prompt_content_rows(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local rows = 0
    for _, line in ipairs(lines) do
        local width = vim.fn.strdisplaywidth(line)
        rows = rows + math.max(1, math.ceil((width + 1) / PROMPT_TEXT_WIDTH))
    end
    return math.max(1, math.min(rows, PROMPT_MAX_ROWS))
end

---Computes the editor-relative anchor for a new prompt window.
---
---The prompt opens below the cursor when enough screen space remains, otherwise
---it opens above. Columns are clamped so the border stays on screen.
---@return integer
---@return integer
local function prompt_anchor()
    local float_h = PROMPT_MAX_ROWS + PROMPT_DECORATION_ROWS + PROMPT_LAYOUT.BORDER_ROWS
    local screen_row = vim.fn.screenrow()
    local screen_lines = vim.o.lines - vim.o.cmdheight
    local row
    if screen_row + float_h + PROMPT_LAYOUT.BELOW_CURSOR_MARGIN <= screen_lines then
        row = screen_row -- open below cursor (0-indexed: screenrow is 1-indexed)
    else
        row = screen_row - float_h - PROMPT_LAYOUT.ABOVE_CURSOR_MARGIN
    end
    row = math.max(0, row)

    local screen_col = vim.fn.screencol() - 1 -- 0-indexed
    local col = math.min(screen_col, vim.o.columns - PROMPT_WIDTH - PROMPT_LAYOUT.RIGHT_MARGIN)
    col = math.max(0, col)

    return row, col
end

---Builds the floating window configuration for the prompt.
---@param buf integer
---@param anchor_row integer
---@param anchor_col integer
---@return vim.api.keyset.win_config
local function prompt_win_config(buf, anchor_row, anchor_col)
    local custom = require("aru.custom")
    local rows = prompt_content_rows(buf)
    return {
        relative = "editor",
        row = anchor_row,
        col = anchor_col,
        width = PROMPT_WIDTH,
        height = rows + PROMPT_DECORATION_ROWS,
        style = constants.UI.STYLE_MINIMAL,
        border = custom.border or constants.UI.BORDER_ROUNDED,
        title = " prompt ",
        title_pos = constants.UI.TITLE_POS_LEFT,
        zindex = PROMPT_LAYOUT.ZINDEX,
    }
end

---Renders placeholder and footer virtual text for the prompt.
---@param state PromptState
---@return nil
local function render_footer(state)
    local buf = state.buf
    local total = vim.api.nvim_buf_line_count(buf)
    local footer_idx = total - 1 -- 0-indexed last prompt line
    local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    local show_placeholder = total == 1 and first_line == ""

    local footer_padding = math.max(0, PROMPT_TEXT_WIDTH - vim.fn.strdisplaywidth(FOOTER_TEXT))
    local opts = {
        virt_lines = {
            { { "", "Normal" } },
            { { string.rep(" ", footer_padding) .. FOOTER_TEXT, constants.UI.HIGHLIGHT_COMMENT } },
        },
        virt_lines_above = false,
    }

    if show_placeholder then
        opts.virt_text = { { PLACEHOLDER_TEXT, constants.UI.HIGHLIGHT_COMMENT } }
        opts.virt_text_pos = "overlay"
    end

    vim.api.nvim_buf_clear_namespace(buf, state.footer_ns, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, state.footer_ns, footer_idx, 0, opts)
end

---Resizes the prompt and refreshes its footer decorations.
---@param state PromptState
---@return nil
local function resize_prompt(state)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    local cfg = prompt_win_config(state.buf, state.anchor_row, state.anchor_col)
    vim.api.nvim_win_set_config(state.win, cfg)
    render_footer(state)
end

---Closes the prompt and releases its Neovim resources.
---@return nil
local function close_prompt()
    if not _prompt_state then return end
    local state = _prompt_state
    _prompt_state = nil

    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)

    ui.close_win_buf(state.win, state.buf)

    vim.cmd("stopinsert")
end

---Reads and trims all prompt buffer text.
---@param buf integer
---@return string
local function read_prompt_text(buf)
    local content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return util.trim(table.concat(content_lines, "\n"))
end

---Submits the prompt contents to a destination and closes the prompt.
---
---Empty prompts are allowed when context exists. Completely empty submissions are
---discarded instead of sending a blank request.
---@param destination AgentDestination
---@return nil
local function submit_prompt(destination)
    if not _prompt_state then return end
    local state = _prompt_state

    local prompt_text = read_prompt_text(state.buf)
    local context = state.context
    local send = state.send

    close_prompt()

    if prompt_text == "" and vim.tbl_isempty(context) then return end

    send({
        destination = destination,
        prompt = prompt_text ~= "" and prompt_text or nil,
        context = context,
        submit = true,
    })
end

---Inserts a newline into the prompt without submitting it.
---
---`<CR>` is reserved for submit, so multiline prompt editing uses this explicit
---mapping instead.
---@return nil
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

---Opens the floating prompt and snapshots context immediately.
---
---If a prompt is already open, focus returns to that window rather than creating
---a second prompt. The prompt closes on window leave to avoid stale context.
---@param opts AgentPromptOpenOpts|nil
---@param deps AgentPromptDeps
---@return nil
---Example:
---```lua
---require("aru.agent.prompt").open({}, {
---  collect_context = require("aru.agent.context").collect,
---  send = require("aru.agent").send,
---})
---```
function M.open(opts, deps)
    opts = opts or {}

    if _prompt_state then
        if vim.api.nvim_win_is_valid(_prompt_state.win) then
            pcall(vim.api.nvim_set_current_win, _prompt_state.win)
            return
        end
        close_prompt()
    end

    local context = deps.collect_context(opts.surrounding_lines)

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

    ---@type PromptState
    local state = {
        buf = buf,
        win = win,
        footer_ns = footer_ns,
        context = context,
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
    for _, mapping in ipairs(PROMPT_KEYMAPS) do
        local destination = mapping.destination
        vim.keymap.set(
            mapping.modes,
            mapping.lhs,
            function() submit_prompt(destination) end,
            map_opts
        )
    end
    vim.keymap.set({ "n", "i" }, PROMPT_NEWLINE_KEY, insert_prompt_newline, map_opts)
    vim.keymap.set({ "n", "i" }, PROMPT_CLOSE_KEY, close_prompt, map_opts)

    vim.cmd("startinsert")
end

return M
