---@module "aru.agent"
---Coordinates Neovim-to-agent handoffs for editor context, tmux delivery,
---scratch runs, read floats, code generation, and the prompt UI. This module is
---the public facade; destination-specific UI state lives under `aru.agent.*`.
---
---Example:
---```lua
---local agent = require("aru.agent")
---agent.setup({ executable = "pi-dev", target_window_name = "agent" })
---agent.send({ destination = "read", prompt = "Explain this code" })
---```

---Defines the supported request destinations.
---
---`current` and `session` target an existing tmux agent pane. `read`,
---`scratch`, and `generate` start runtime processes from Neovim.
---@alias AgentDestination "current"|"session"|"read"|"scratch"|"generate"

---Describes a user request before it is normalized into an agent payload.
---
---Missing destinations default to `current`. Missing context becomes an empty
---list. `submit` only affects tmux destinations and defaults to true.
---@class AgentRequest
---@field destination AgentDestination|nil
---@field prompt string|nil
---@field submit boolean|nil
---@field context AgentContextItem[]|nil
---@field preset string|nil

---Describes the normalized payload passed to destination implementations.
---
---Payloads capture the current working directory at send time and keep optional
---prompt/preset fields separate so renderers can omit empty sections cleanly.
---@class AgentPayload
---@field version integer
---@field source "nvim"
---@field cwd string
---@field prompt string|nil
---@field preset string|nil
---@field context AgentContextItem[]

---Describes the tmux pane selected as an interactive agent target.
---
---The current command is used by `validate_target` to avoid pasting prompts into
---an unrelated shell or editor pane.
---@class AgentTmuxTarget
---@field session_name string
---@field window_id string
---@field window_name string
---@field pane_id string
---@field pane_current_command string

---Configures the agent facade and concrete runtime integration.
---
---All fields are optional and merge over the defaults. `validate_target` can be
---used when the runtime command is not the default `pi` executable name.
---@class AgentConfig
---@field target_window_name string|nil
---@field session_command string|nil
---@field executable string|nil
---@field runtime_args string[]|nil
---@field runtime_label string|nil
---@field validate_target fun(target: AgentTmuxTarget): boolean|nil

local M = {}

local logger = require("aru.log"):bind("agent")
local constants = require("aru.agent.constants")
local util = require("aru.agent.util")
local context = require("aru.agent.context")
local read_mode = require("aru.agent.read")
local generate_mode = require("aru.agent.generate")
local prompt_ui = require("aru.agent.prompt")

---@type AgentConfig
local DEFAULT_CONFIG = {
    target_window_name = "agent",
    session_command = "/nvim-session",
    executable = "pi-dev",
}

---@type AgentConfig
local config = vim.deepcopy(DEFAULT_CONFIG)

---Runs a system command synchronously and logs failures.
---
---Returns the completed result as the first value on success. On non-zero exit,
---returns nil plus the failed result so callers can inspect stderr or code.
---@param cmd string[]
---@param opts vim.SystemOpts|nil
---@return vim.SystemCompleted|nil
---@return vim.SystemCompleted|nil
local function system_sync(cmd, opts)
    opts = opts or {}
    opts.text = true

    local result = vim.system(cmd, opts):wait()
    if result.code ~= 0 then
        logger:error("command failed: %s", vim.inspect({ cmd = cmd, result = result }))
        return nil, result
    end

    return result, nil
end

---Returns a display/command label for a configured executable path.
---@param executable string|nil
---@return string
local function executable_label(executable)
    local label = vim.fn.fnamemodify(executable or "", ":t")
    return label ~= "" and label or "agent"
end

---Returns the configured runtime label for UI and default target validation.
---@return string
local function runtime_label()
    return config.runtime_label or executable_label(config.executable or DEFAULT_CONFIG.executable)
end

---Checks whether a tmux target looks like the configured agent TUI.
---@param target AgentTmuxTarget
---@return boolean
local function default_validate_target(target)
    local expected = runtime_label()
    return target.pane_current_command == expected
        or target.pane_current_command == constants.RUNTIME.LEGACY_TUI_COMMAND
end

---Gets the current tmux session name.
---@return string|nil
local function current_tmux_session()
    local result = system_sync({
        constants.TMUX.COMMAND,
        "display-message",
        "-p",
        constants.TMUX.FORMATS.SESSION_NAME,
    })
    if not result then return nil end
    return util.trim(result.stdout)
end

---Finds a tmux window id by exact window name inside a session.
---@param session_name string
---@param window_name string
---@return string|nil
local function find_window_id(session_name, window_name)
    local result = system_sync({
        constants.TMUX.COMMAND,
        "list-windows",
        "-t",
        session_name,
        "-F",
        constants.TMUX.FORMATS.WINDOWS,
    })
    if not result then return nil end

    for _, line in ipairs(vim.split(result.stdout, "\n", { plain = true, trimempty = true })) do
        local window_id, name = line:match("^([^\t]+)\t(.+)$")
        if name == window_name then return window_id end
    end

    return nil
end

---Finds the active pane and command for a tmux window.
---@param window_id string
---@return string|nil
---@return string|nil
local function active_pane_in_window(window_id)
    local result = system_sync({
        constants.TMUX.COMMAND,
        "list-panes",
        "-t",
        window_id,
        "-F",
        constants.TMUX.FORMATS.PANES,
    })
    if not result then return nil, nil end

    for _, line in ipairs(vim.split(result.stdout, "\n", { plain = true, trimempty = true })) do
        local pane_id, pane_active, pane_current_command = line:match("^([^\t]+)\t([^\t]+)\t(.+)$")
        if pane_active == "1" then return pane_id, pane_current_command end
    end

    return nil, nil
end

---Finds and validates the configured agent pane in the current tmux session.
---@return AgentTmuxTarget|nil
local function find_current_agent_target()
    local session_name = current_tmux_session()
    if not session_name then return nil end

    local window_name = config.target_window_name or DEFAULT_CONFIG.target_window_name
    local window_id = find_window_id(session_name, window_name)
    if not window_id then
        logger:warn("No tmux window named %q in current session", window_name)
        return nil
    end

    local pane_id, pane_current_command = active_pane_in_window(window_id)
    if not pane_id then
        logger:warn("No active pane found in tmux window %q", window_name)
        return nil
    end

    local target = {
        session_name = session_name,
        window_id = window_id,
        window_name = window_name,
        pane_id = pane_id,
        pane_current_command = pane_current_command or "",
    }

    local validate = config.validate_target or default_validate_target
    if not validate(target) then
        logger:error(
            "Active pane in %q does not look like an agent runtime: %s",
            window_name,
            target.pane_current_command
        )
        return nil
    end

    return target
end

---Returns a markdown fence longer than any backtick run in text.
---@param text string|nil
---@return string
local function markdown_fence(text)
    local longest = 0
    for run in (text or ""):gmatch("`+") do
        longest = math.max(longest, #run)
    end
    return string.rep("`", math.max(3, longest + 1))
end

---Renders an agent payload into the text protocol pasted or piped to the runtime.
---
---The output is markdown-like: preset first, prompt second, then fenced context
---blocks labeled with kind, path, and source line range when available.
---@param payload AgentPayload
---@return string
local function render_payload(payload)
    local out = {}

    if payload.preset and payload.preset ~= "" then
        table.insert(out, payload.preset)
        table.insert(out, "")
    end

    if payload.prompt and payload.prompt ~= "" then
        table.insert(out, payload.prompt)
        table.insert(out, "")
    end

    for _, item in ipairs(payload.context or {}) do
        local label = item.kind
        if item.path then label = label .. ": " .. item.path end
        if item.start_line and item.end_line then
            label = ("%s:%d-%d"):format(label, item.start_line, item.end_line)
        end

        local fence = markdown_fence(item.text)
        table.insert(out, ("--- %s ---"):format(label))
        if item.filetype and item.filetype ~= "" then
            table.insert(out, ("%s%s"):format(fence, item.filetype))
        else
            table.insert(out, fence)
        end
        table.insert(out, item.text or "")
        table.insert(out, fence)
        table.insert(out, "")
    end

    return table.concat(out, "\n"):gsub("%s+$", "")
end

---Writes text to a temporary file for tmux or runtime handoff.
---@param text string
---@return string|nil
local function write_temp(text)
    local path = vim.fn.tempname()
    local ok, err = pcall(vim.fn.writefile, vim.split(text, "\n", { plain = true }), path)
    if not ok then
        logger:error("Failed to write agent temp file: %s", err)
        return nil
    end
    return path
end

---Deletes a temporary payload file after the tmux command has had time to read it.
---@param path string
---@return nil
local function cleanup_temp_later(path)
    vim.defer_fn(
        function() pcall(vim.fn.delete, path) end,
        constants.SESSION.TEMP_CLEANUP_DELAY_MS
    )
end

---Pastes text into a tmux pane through a temporary tmux buffer.
---
---The tmux buffer path avoids shell quoting issues and preserves multiline text
---exactly. Returns false when any tmux command fails.
---@param pane_id string
---@param text string
---@param submit boolean
---@return boolean
local function paste_to_pane(pane_id, text, submit)
    local path = write_temp(text)
    if not path then return false end

    -- tmux paste-buffer avoids shell quoting problems and preserves multiline text.
    local buffer_name = constants.TMUX.BUFFER_PREFIX .. tostring(vim.uv.hrtime())
    local ok = system_sync({ constants.TMUX.COMMAND, "load-buffer", "-b", buffer_name, path })
        ~= nil
    pcall(vim.fn.delete, path)
    if not ok then return false end

    if
        not system_sync({
            constants.TMUX.COMMAND,
            "paste-buffer",
            "-t",
            pane_id,
            "-b",
            buffer_name,
            "-d",
        })
    then
        return false
    end

    if submit then
        if
            not system_sync({
                constants.TMUX.COMMAND,
                "send-keys",
                "-t",
                pane_id,
                constants.TMUX.SUBMIT_KEY,
            })
        then
            return false
        end
    end

    return true
end

---Builds a normalized payload from a caller request.
---@param request AgentRequest
---@return AgentPayload
local function build_payload(request)
    return {
        version = constants.PAYLOAD.VERSION,
        source = constants.PAYLOAD.SOURCE,
        cwd = vim.fn.getcwd(),
        prompt = request.prompt,
        preset = request.preset,
        context = request.context or {},
    }
end

---Sends a rendered payload to the current interactive tmux agent pane.
---@param payload AgentPayload
---@param submit boolean
---@return boolean
local function send_current(payload, submit)
    local target = find_current_agent_target()
    if not target then return false end

    local rendered = render_payload(payload)
    logger:debug(
        "send_current -> pane %s (submit=%s)\n%s",
        target.pane_id,
        tostring(submit),
        rendered
    )
    return paste_to_pane(target.pane_id, rendered, submit)
end

---Sends a session command that points the agent runtime at a payload file.
---@param payload AgentPayload
---@param submit boolean
---@return boolean
local function send_session(payload, submit)
    local target = find_current_agent_target()
    if not target then return false end

    local rendered = render_payload(payload)
    local payload_path = write_temp(rendered)
    if not payload_path then return false end

    local command = ("%s --file %s"):format(
        config.session_command,
        vim.fn.shellescape(payload_path)
    )
    logger:info(
        "send_session -> pane %s (submit=%s)\npayload:\n%s\ncommand: %s",
        target.pane_id,
        tostring(submit),
        rendered,
        command
    )

    local ok = paste_to_pane(target.pane_id, command, submit)
    if ok and submit then
        cleanup_temp_later(payload_path)
    elseif not ok then
        pcall(vim.fn.delete, payload_path)
    end
    return ok
end

---Starts read mode for a payload.
---@param payload AgentPayload
---@return boolean
local function send_read(payload)
    return read_mode.send(payload, {
        render_payload = render_payload,
        executable = config.executable or DEFAULT_CONFIG.executable,
        runtime_args = config.runtime_args,
        runtime_label = runtime_label(),
    })
end

---Starts generate mode for a payload.
---@param payload AgentPayload
---@return boolean
local function send_generate(payload)
    return generate_mode.send(payload, {
        render_payload = render_payload,
        executable = config.executable or DEFAULT_CONFIG.executable,
        runtime_args = config.runtime_args,
    })
end

---Starts a detached scratch runtime process for a payload.
---@param payload AgentPayload
---@return boolean
local function send_scratch(payload)
    local message = render_payload(payload)
    local executable = config.executable or DEFAULT_CONFIG.executable

    local cmd = { executable }
    vim.list_extend(cmd, constants.RUNTIME.SCRATCH_ARGS)

    vim.system(cmd, { text = true, stdin = message }, function(result)
        if result.code == 0 then
            logger:info("scratch agent run completed")
            return
        end

        logger:error("scratch agent run failed (%d): %s", result.code, util.stderr_summary(result))
    end)

    return true
end

local SEND_HANDLERS = {
    [constants.DESTINATION.CURRENT] = function(payload, submit)
        return send_current(payload, submit)
    end,
    [constants.DESTINATION.SESSION] = function(payload, submit)
        return send_session(payload, submit)
    end,
    [constants.DESTINATION.READ] = function(payload) return send_read(payload) end,
    [constants.DESTINATION.SCRATCH] = function(payload) return send_scratch(payload) end,
    [constants.DESTINATION.GENERATE] = function(payload) return send_generate(payload) end,
}

---Configures the agent facade.
---
---Merges the provided partial config over built-in defaults. Passing nil resets
---to the default configuration.
---@param opts AgentConfig|nil
---@return nil
---Example:
---```lua
---require("aru.agent").setup({ executable = "pi-dev", target_window_name = "agent" })
---```
function M.setup(opts)
    config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_CONFIG), opts or {})
end

---Dispatches a request to the selected agent destination.
---
---Returns false for unknown destinations, invalid buffers, missing tmux targets,
---or failed tmux commands. Async runtime failures are logged after scheduling.
---@param request AgentRequest|nil
---@return boolean
---Example:
---```lua
---require("aru.agent").send({ destination = "read", prompt = "Summarize this buffer" })
---```
function M.send(request)
    request = request or {}
    local destination = request.destination or constants.DESTINATION.CURRENT
    local submit = request.submit ~= false
    local payload = build_payload(request)
    local handler = SEND_HANDLERS[destination]

    if not handler then
        logger:error("Unknown agent destination: %s", destination)
        return false
    end

    return handler(payload, submit)
end

---@param destination AgentDestination
---@param opts AgentRequest|nil
---@return boolean
local function send_to(destination, opts)
    local request = vim.tbl_extend("force", {}, opts or {}, { destination = destination })
    return M.send(request)
end

---Sends a request to the current interactive tmux agent pane.
---@param opts AgentRequest|nil
---@return boolean
function M.current(opts) return send_to(constants.DESTINATION.CURRENT, opts) end

---Sends a request through the configured session command in the tmux agent pane.
---@param opts AgentRequest|nil
---@return boolean
function M.session(opts) return send_to(constants.DESTINATION.SESSION, opts) end

---Starts a scratch runtime process for a request.
---@param opts AgentRequest|nil
---@return boolean
function M.scratch(opts) return send_to(constants.DESTINATION.SCRATCH, opts) end

---Starts generate mode for a request at the current cursor.
---@param opts AgentRequest|nil
---@return boolean
function M.generate(opts) return send_to(constants.DESTINATION.GENERATE, opts) end

---Opens the floating prompt and snapshots editor context immediately.
---@param opts AgentPromptOpenOpts|nil
---@return nil
---Example:
---```lua
---vim.keymap.set("n", "<leader>aa", function() require("aru.agent").prompt() end)
---```
function M.prompt(opts)
    return prompt_ui.open(opts, {
        collect_context = context.collect,
        send = M.send,
    })
end

---Restores the last completed read response without re-querying the runtime.
---@return nil
function M.restore_read() return read_mode.restore() end

---Focuses the read float, restores it when closed, or jumps back when already focused.
---@return nil
function M.focus_read() return read_mode.focus() end

---Scrolls the read float from any current window.
---@param direction "down"|"up"
---@return nil
function M.scroll_read(direction) return read_mode.scroll(direction) end

---Closes the read float from any current window.
---@return nil
function M.close_read() return read_mode.close() end

M._build_payload = build_payload
M._render_payload = render_payload
M._find_current_agent_target = find_current_agent_target
M._collect_context = context.collect

return M
