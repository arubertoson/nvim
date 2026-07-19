---@module "aru.agent.channels.tmux"
---Pastes an agent handoff into the active tmux agent pane.

local M = {}

local log = require("aru.log"):bind("agent.channels.tmux")
local constants = require("aru.agent.constants")

local function system_sync(cmd)
    local result = vim.system(cmd, { text = true }):wait()
    if result.code ~= 0 then
        log:error("tmux command failed: %s", vim.inspect(cmd))
        return nil
    end
    return result
end

local function current_tmux_session()
    local result = system_sync({
        constants.TMUX.COMMAND,
        "display-message",
        "-p",
        constants.TMUX.FORMATS.SESSION_NAME,
    })
    if not result then return nil end
    return vim.trim(result.stdout)
end

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
        local pane_id, active, pane_cmd = line:match("^([^\t]+)\t([^\t]+)\t(.+)$")
        if active == "1" then return pane_id, pane_cmd end
    end
    return nil, nil
end

---@param config aru.agent.config.Opts
---@return { pane_id: string }|nil
local function find_target(config)
    local session = current_tmux_session()
    if not session then return nil end

    local window_name = config.target_window_name or "agent"
    local window_id = find_window_id(session, window_name)
    if not window_id then
        log:warn("No tmux window named %q in current session", window_name)
        return nil
    end

    local pane_id, pane_cmd = active_pane_in_window(window_id)
    if not pane_id then
        log:warn("No active pane in tmux window %q", window_name)
        return nil
    end

    local expected = vim.fn.fnamemodify(config.executable or "", ":t")
    if pane_cmd ~= expected then
        log:error("Pane running %q, expected %q", pane_cmd, expected)
        return nil
    end

    return { pane_id = pane_id }
end

local function write_temp(text)
    local path = vim.fn.tempname()
    local ok, err = pcall(vim.fn.writefile, vim.split(text, "\n", { plain = true }), path)
    if not ok then
        log:error("Failed to write temp file: %s", err)
        return nil
    end
    return path
end

local function paste_to_pane(pane_id, text, submit)
    local path = write_temp(text)
    if not path then return false end

    local buf_name = constants.TMUX.BUFFER_PREFIX .. tostring(vim.uv.hrtime())
    local ok = system_sync({ constants.TMUX.COMMAND, "load-buffer", "-b", buf_name, path }) ~= nil
    pcall(vim.fn.delete, path)
    if not ok then return false end

    if
        not system_sync({
            constants.TMUX.COMMAND,
            "paste-buffer",
            "-t",
            pane_id,
            "-b",
            buf_name,
            "-d",
        })
    then
        return false
    end

    if submit then
        return system_sync({
            constants.TMUX.COMMAND,
            "send-keys",
            "-t",
            pane_id,
            constants.TMUX.SUBMIT_KEY,
        }) ~= nil
    end

    return true
end

---@param transport aru.agent.channels.Transport
---@param ctx aru.agent.ConfigState
---@return boolean
function M.send(transport, ctx)
    local target = find_target(ctx.config)
    if not target then return false end

    return paste_to_pane(target.pane_id, transport.message, true)
end

return M
