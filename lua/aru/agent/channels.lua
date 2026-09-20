---@module "aru.agent.channels"
---Registry for agent delivery channels. `get` only resolves a destination
---to its channel module; validation and side effects happen in `channel.send`.

local M = {}

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

---@param destination aru.agent.channels.Destination
---@return aru.agent.channels.Channel
function M.get(destination)
    local load = CHANNELS[destination]
    if not load then error("Missing channel for destination: " .. destination) end
    return load()
end

return M
