---@module "aru.agent.channels.editor"
---Streams agent output for code generation and inserts the completed answer at
---the original cursor position. This channel owns ghost text, spinner updates,
---JSON event processing, and final buffer insertion.

local M = {}

local logger = require("aru.log"):bind("agent.channels.editor")
local constants = require("aru.agent.constants")
local lines = require("aru.agent.lines")
local progress = require("aru.agent.progress")
local stream = require("aru.agent.stream")
local process = require("aru.agent.process")

local EDITOR_SYSTEM_PROMPT = [[You are a code generation assistant embedded in a text editor.
Reply ONLY with the code that should be inserted at the cursor position.
Do NOT include any explanation, markdown fences, or prose.
Do NOT repeat code that already exists around the cursor.
Output raw code only.]]

---@class aru.agent.channels.editor.State: aru.agent.progress.State
---@field buf integer
---@field row integer
---@field col integer
---@field ns integer
---@field ghost_id integer|nil
---@field answer { lines: string[], pending: string }

---@type aru.agent.channels.editor.State|nil
local _state = nil

---@param state aru.agent.channels.editor.State
local function clear_ghost(state)
    if state.ghost_id then
        pcall(vim.api.nvim_buf_del_extmark, state.buf, state.ns, state.ghost_id)
        state.ghost_id = nil
    end
end

---@param state aru.agent.channels.editor.State
local function refresh_ghost(state)
    clear_ghost(state)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    local text = " " .. progress.frame(state) .. " " .. state.phrase
    state.ghost_id = vim.api.nvim_buf_set_extmark(state.buf, state.ns, state.row, state.col, {
        virt_text = { { text, constants.UI.HIGHLIGHT_COMMENT } },
        virt_text_pos = "inline",
        hl_mode = "combine",
    })
end

---@param state aru.agent.channels.editor.State
local function start_spinner(state)
    progress.start(state, {
        is_current = function() return _state == state end,
        refresh = function() refresh_ghost(state) end,
    })
end

---@param state aru.agent.channels.editor.State
local function stop_spinner(state) progress.stop(state) end

local function cancel_active()
    if not _state then return end
    stop_spinner(_state)
    clear_ghost(_state)
    _state = nil
end

---@param state aru.agent.channels.editor.State
local function insert_answer(state)
    clear_ghost(state)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end

    local answer_lines = lines.flush(state.answer)
    if vim.tbl_isempty(answer_lines) then return end

    local row, col = state.row, state.col
    local cur_line = vim.api.nvim_buf_get_lines(state.buf, row, row + 1, false)[1] or ""
    local before = cur_line:sub(1, col)
    local after = cur_line:sub(col + 1)

    local new_lines = {}
    for i, ln in ipairs(answer_lines) do
        new_lines[i] = (i == 1) and (before .. ln) or ln
    end
    new_lines[#new_lines] = new_lines[#new_lines] .. after

    vim.api.nvim_buf_set_lines(state.buf, row, row + 1, false, new_lines)
    pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
end

---@param transport aru.agent.channels.Transport
---@param _ctx aru.agent.ConfigState|nil
---@return boolean
function M.send(transport, _ctx)
    local buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then return false end

    local pos = vim.api.nvim_win_get_cursor(0)
    local row = pos[1] - 1
    local col = pos[2]

    cancel_active()

    ---@type aru.agent.channels.editor.State
    local state = {
        buf = buf,
        row = row,
        col = col,
        ns = vim.api.nvim_create_namespace(constants.NAMESPACE.EDITOR),
        ghost_id = nil,
        answer = { lines = {}, pending = "" },
    }
    progress.init(state)
    _state = state

    local stdin = transport.message == ""
        and EDITOR_SYSTEM_PROMPT
        or EDITOR_SYSTEM_PROMPT .. "\n\nUser request: " .. transport.message
    logger:info("editor channel send row=%d col=%d:\n%s", row, col, stdin)

    refresh_ghost(state)
    start_spinner(state)

    transport.run(stdin, function(event)
        if _state ~= state then return end
        stream.dispatch(event, {
            on_thinking = function()
                if progress.update_phrase(state) then refresh_ghost(state) end
            end,
            on_text = function(delta)
                lines.push(state.answer, delta)
            end,
        })
    end, function(result)
        if _state ~= state then return end
        _state = nil
        stop_spinner(state)

        if result.code ~= 0 then
            logger:error(
                "editor channel failed (%d): %s",
                result.code,
                process.stderr_summary(result)
            )
            clear_ghost(state)
            return
        end

        insert_answer(state)
    end)

    return true
end

return M
