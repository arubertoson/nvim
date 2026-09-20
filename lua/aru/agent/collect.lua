---@module "aru.agent.collect"
---Resolves named context collectors into payload items.

local M = {}

---@enum aru.agent.collect.Type
M.COLLECT = {
    BLOCK = "block",
    DIAGNOSTIC = "diagnostic",
}

local providers = {
    [M.COLLECT.BLOCK] = require("aru.agent.collect.block"),
    [M.COLLECT.DIAGNOSTIC] = require("aru.agent.collect.diagnostic"),
}

---@param invocation aru.agent.InvocationState
---@param names aru.agent.collect.Type[]
---@return aru.agent.payload.ContextItem[]
function M.resolve(invocation, names)
    ---@type aru.agent.payload.ContextItem[]
    local items = {}
    for _, name in ipairs(names) do
        local provider = providers[name]
        if not provider then error("Unknown collect provider: " .. tostring(name)) end
        local item = provider.collect(invocation)
        if item then table.insert(items, item) end
    end

    return items
end

return M
