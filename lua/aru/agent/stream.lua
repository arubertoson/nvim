---@module "aru.agent.stream"
---Dispatches decoded JSON stream events to channel-specific handlers.

local M = {}

local constants = require("aru.agent.constants")

---@class aru.agent.stream.Handlers
---@field on_thinking fun(delta: string)|nil
---@field on_text fun(delta: string)|nil

---@param event table
---@param handlers aru.agent.stream.Handlers
function M.dispatch(event, handlers)
    if event.type ~= constants.EVENT.MESSAGE_UPDATE then return end
    local ev = event.assistantMessageEvent
    if not ev then return end

    if ev.type == constants.EVENT.THINKING_DELTA and type(ev.delta) == "string" then
        if handlers.on_thinking then handlers.on_thinking(ev.delta) end
        return
    end

    if ev.type == constants.EVENT.TEXT_DELTA and type(ev.delta) == "string" then
        if handlers.on_text then handlers.on_text(ev.delta) end
    end
end

return M
