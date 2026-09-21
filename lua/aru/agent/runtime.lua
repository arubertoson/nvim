---@module "aru.agent.runtime"
local M = {}

local constants = require("aru.agent.constants")

---@class aru.agent.runtime.NoSessionTarget
---@field kind "none"

---@class aru.agent.runtime.ExplicitSessionTarget
---@field kind "explicit"
---@field id string

---@alias aru.agent.runtime.SessionTarget aru.agent.runtime.NoSessionTarget|aru.agent.runtime.ExplicitSessionTarget

---@class aru.agent.runtime.Args
---@field JSON_ARGS string[]
---@field NO_SESSION string
---@field PRESET string
---@field SESSION_DIR string
---@field SESSION_ID string|nil
---@field TOOLS string

---@class aru.agent.runtime.Setup
---@field tools string[]|nil

---@param runtime aru.agent.runtime.Args
---@param args string[]
---@param target aru.agent.runtime.SessionTarget
---@param session_dir string
local function extend_with_session_args(runtime, args, target, session_dir)
    if target.kind == "none" then
        table.insert(args, runtime.NO_SESSION)
        return
    end

    if not runtime.SESSION_ID then
        error("Runtime cannot target an explicit agent session: SESSION_ID is not configured")
    end

    table.insert(args, runtime.SESSION_DIR)
    table.insert(args, session_dir)
    table.insert(args, runtime.SESSION_ID)
    table.insert(args, target.id)
end

---@param runtime_name string
---@return aru.agent.runtime.Args
local function runtime_config(runtime_name)
    local runtime = constants.RUNTIME[runtime_name]
    if not runtime then error("No runtime config: " .. tostring(runtime_name)) end
    return runtime
end

---@param ctx aru.agent.ConfigState
function M.assert_explicit_session(ctx)
    local runtime = runtime_config(ctx.config.runtime)
    if not runtime.SESSION_ID then
        error("Runtime cannot target an explicit agent session: " .. ctx.config.runtime)
    end
end

---@param ctx aru.agent.ConfigState
---@param request aru.agent.Request
---@param target aru.agent.runtime.SessionTarget
---@param setup aru.agent.runtime.Setup
---@return string[]
function M.command(ctx, request, target, setup)
    local args = { ctx.config.executable }
    local runtime = runtime_config(ctx.config.runtime)

    if request.preset and request.preset ~= "" then
        table.insert(args, runtime.PRESET)
        table.insert(args, request.preset)
    end

    if setup.tools then
        table.insert(args, runtime.TOOLS)
        table.insert(args, table.concat(setup.tools, ","))
    end

    vim.list_extend(args, runtime.JSON_ARGS)
    extend_with_session_args(runtime, args, target, ctx.config.session_dir)

    return args
end

return M
