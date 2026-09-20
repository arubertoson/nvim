---@module "aru.agent.channels"
---Registry for agent delivery channels. `get` only resolves a destination
---to its channel module; validation and side effects happen in `channel.send`.

local M = {}

local log = require("aru.log")

---@enum aru.agent.channels.Destination
M.DESTINATION = {
    FLOAT = "float",
    EDITOR = "editor",
}

---@class aru.agent.channels.Transport
---@field message string
---@field response aru.agent.Response|nil
---@field run fun(stdin: string, on_event: fun(event: table), on_exit: fun(result: vim.SystemCompleted)): vim.SystemObj|nil

---@class aru.agent.channels.Channel
---@field send fun(transport: aru.agent.channels.Transport, ctx: aru.agent.ConfigState): boolean

local CHANNELS = {
    [M.DESTINATION.FLOAT] = function() return require("aru.agent.channels.float") end,
    [M.DESTINATION.EDITOR] = function() return require("aru.agent.channels.editor") end,
}

---Returns the channel for a destination without validating availability.
---@param destination aru.agent.channels.Destination
---@return aru.agent.channels.Channel|nil
function M.get(destination)
    local load = CHANNELS[destination]
    if not load then
        log.error("Unknown destination", destination)
        return nil
    end

    return load()
end

return M
