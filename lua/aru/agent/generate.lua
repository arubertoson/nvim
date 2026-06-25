---@module "aru.agent.generate"
---Streams agent output for code generation and inserts the completed answer at
---the original cursor position. This module owns generate-mode state, ghost text,
---spinner updates, JSON event processing, and final buffer insertion.

local M = {}

local logger = require("aru.log"):bind("agent")
local constants = require("aru.agent.constants")
local lines = require("aru.agent.lines")
local progress = require("aru.agent.progress")
local stream = require("aru.agent.stream")
local util = require("aru.agent.util")

local GENERATE_SYSTEM_PROMPT = [[You are a code generation assistant embedded in a text editor.
Reply ONLY with the code that should be inserted at the cursor position.
Do NOT include any explanation, markdown fences, or prose.
Do NOT repeat code that already exists around the cursor.
Output raw code only.]]

---Describes the assistant message event emitted by the JSON runtime stream.
---
---Generate mode consumes `thinking_delta` for ghost-text updates and
---`text_delta` for the eventual inserted answer. Unknown event types are ignored.
---@class AgentGenerateAssistantMessageEvent
---@field type "thinking_delta"|"text_delta"
---@field delta string|nil

---Describes a parsed JSON runtime event used by generate mode.
---
---Only `message_update` events with an assistant payload affect generation.
---@class AgentGenerateStreamEvent
---@field type string
---@field assistantMessageEvent AgentGenerateAssistantMessageEvent|nil

---Configures dependencies supplied by the agent facade for generate mode.
---
---Passing dependencies in keeps this module focused on insertion behavior rather
---than global agent configuration.
---@class AgentGenerateSendOpts
---@field render_payload fun(payload: AgentPayload): string
---@field executable string
---@field runtime_args string[]|nil

---Tracks one in-flight code generation request.
---
---The insertion point is captured before streaming starts. Answer chunks are
---accumulated off-buffer and inserted only after the runtime exits successfully,
---so partial generated code never mutates the source buffer.
---@class GenerateState: AgentProgressState
---@field buf integer
---@field row integer
---@field col integer
---@field ns integer
---@field ghost_id integer|nil
---@field answer { lines: string[], pending: string }

---@type GenerateState|nil
local _gen_state = nil

---Clears the current ghost-text extmark.
---@param state GenerateState
---@return nil
local function gen_clear_ghost(state)
    if state.ghost_id then
        pcall(vim.api.nvim_buf_del_extmark, state.buf, state.ns, state.ghost_id)
        state.ghost_id = nil
    end
end

---Renders the current spinner frame and phrase as inline ghost text.
---@param state GenerateState
---@return nil
local function gen_refresh_ghost(state)
    gen_clear_ghost(state)
    if not vim.api.nvim_buf_is_valid(state.buf) then return end
    local text = " " .. progress.frame(state) .. " " .. state.phrase
    state.ghost_id = vim.api.nvim_buf_set_extmark(state.buf, state.ns, state.row, state.col, {
        virt_text = { { text, constants.UI.HIGHLIGHT_COMMENT } },
        virt_text_pos = "inline",
        hl_mode = "combine",
    })
end

---Starts the generate ghost-text spinner timer.
---@param state GenerateState
---@return nil
local function gen_start_spinner(state)
    progress.start(state, {
        is_current = function() return _gen_state == state end,
        refresh = function() gen_refresh_ghost(state) end,
    })
end

---Stops and closes the generate spinner timer.
---@param state GenerateState
---@return nil
local function gen_stop_spinner(state) progress.stop(state) end

---Cancels the active generate UI state without touching the source buffer.
---@return nil
local function gen_cancel_active()
    if not _gen_state then return end
    gen_stop_spinner(_gen_state)
    gen_clear_ghost(_gen_state)
    _gen_state = nil
end

---Inserts the accumulated answer at the original cursor position.
---
---The current line is split at the captured cursor column. Multiline answers
---replace that single line with the answer spliced between the original prefix
---and suffix.
---@param state GenerateState
---@return nil
local function gen_insert_answer(state)
    gen_clear_ghost(state)
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
    -- Keep the user at the invocation point so generated text does not steal cursor intent.
    pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
end

---Handles one parsed runtime event for generate mode.
---
---Thinking updates only affect ghost text. Text deltas are accumulated in memory
---until final insertion.
---@param state GenerateState
---@param event AgentGenerateStreamEvent
---@return nil
local function gen_handle_event(state, event)
    if event.type ~= constants.EVENT.MESSAGE_UPDATE then return end
    local ev = event.assistantMessageEvent
    if not ev then return end

    if ev.type == constants.EVENT.THINKING_DELTA and type(ev.delta) == "string" then
        if progress.update_phrase(state) then gen_refresh_ghost(state) end
        return
    end

    if ev.type == constants.EVENT.TEXT_DELTA and type(ev.delta) == "string" then
        -- The ghost stays visible until completion so partial code is never inserted into the buffer.
        lines.push(state.answer, ev.delta)
    end
end

---Starts generate mode and streams raw code into the current buffer.
---
---Returns false only when there is no valid current buffer. Runtime failures are
---logged asynchronously and leave the source buffer unchanged.
---@param payload AgentPayload
---@param opts AgentGenerateSendOpts
---@return boolean
---Example:
---```lua
---require("aru.agent").send({ destination = "generate", prompt = "Add error handling" })
---```
function M.send(payload, opts)
    local buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then return false end

    local pos = vim.api.nvim_win_get_cursor(0)
    local row = pos[1] - 1
    local col = pos[2]

    gen_cancel_active()

    ---@type GenerateState
    local state = {
        buf = buf,
        row = row,
        col = col,
        ns = vim.api.nvim_create_namespace(constants.NAMESPACE.GENERATE),
        ghost_id = nil,
        answer = { lines = {}, pending = "" },
    }
    progress.init(state)
    _gen_state = state

    payload = vim.deepcopy(payload)
    if not payload.prompt or payload.prompt == "" then
        payload.prompt = GENERATE_SYSTEM_PROMPT
    else
        payload.prompt = GENERATE_SYSTEM_PROMPT .. "\n\nUser request: " .. payload.prompt
    end

    local message = opts.render_payload(payload)
    local executable = opts.executable
    logger:info("send_generate row=%d col=%d:\n%s", row, col, message)

    gen_refresh_ghost(state)
    gen_start_spinner(state)

    stream.run_json({
        executable = executable,
        args = opts.runtime_args,
        stdin = message,
        on_event = function(event)
            if _gen_state == state then gen_handle_event(state, event) end
        end,
        on_exit = function(result)
            if _gen_state ~= state then return end
            _gen_state = nil
            gen_stop_spinner(state)

            if result.code ~= 0 then
                logger:error(
                    "send_generate failed (%d): %s",
                    result.code,
                    util.stderr_summary(result)
                )
                gen_clear_ghost(state)
                return
            end

            gen_insert_answer(state)
        end,
    })

    return true
end

return M
