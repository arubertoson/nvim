---@module "aru.agent.runtime"
local M = {}

local channels = require("aru.agent.channels")
local constants = require("aru.agent.constants")

---@enum aru.agent.runtime.SessionPolicy
M.SESSION = {
    NEW = "new",
    CONTINUE = "continue",
    NONE = "none",
}

---@class aru.agent.runtime.Args
---@field JSON_ARGS string[]
---@field NO_SESSION string
---@field CONTINUE string
---@field PRESET string
---@field SESSION_DIR string

---@param runtime aru.agent.runtime.Args
---@param args string[]
---@param destination aru.agent.channels.Destination
local function extend_with_destination_args(runtime, args, destination)
    if destination == channels.DESTINATION.TMUX then return end

    local dest_args = runtime.JSON_ARGS
    if not dest_args then error("No JSON_ARGS configured for runtime") end

    for i = 1, #dest_args do
        args[#args + 1] = dest_args[i]
    end
end

---@param runtime aru.agent.runtime.Args
---@param args string[]
---@param policy aru.agent.runtime.SessionPolicy|nil
---@param session_dir string
local function extend_with_session_args(runtime, args, policy, session_dir)
    policy = policy or M.SESSION.NEW

    if policy == M.SESSION.NONE then
        table.insert(args, runtime.NO_SESSION)
        return
    end

    if session_dir and session_dir ~= "" then
        table.insert(args, runtime.SESSION_DIR)
        table.insert(args, session_dir)
    end

    if policy == M.SESSION.CONTINUE then table.insert(args, runtime.CONTINUE) end
end

---@param ctx aru.agent.ConfigState
---@param request aru.agent.Request
---@param session_policy aru.agent.runtime.SessionPolicy|nil
---@return string[]
function M.command(ctx, request, session_policy)
    local args = { ctx.config.executable }
    local runtime_name = ctx.config.runtime
    local runtime = constants.RUNTIME[runtime_name]

    if not runtime then error("No runtime config: " .. tostring(runtime_name)) end

    if request.preset and request.preset ~= "" then
        table.insert(args, runtime.PRESET)
        table.insert(args, request.preset)
    end

    extend_with_destination_args(runtime, args, request.destination)
    extend_with_session_args(runtime, args, session_policy, ctx.config.session_dir)

    return args
end

return M
