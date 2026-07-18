---@module "aru.agent.collect"
---Resolves named context collectors into payload items.

local M = {}

local log = require("aru.log"):bind("collect")

---@enum aru.agent.collect.Type
M.COLLECT = {
    BLOCK = "block",
    DIAGNOSTIC = "diagnostic",
}

local providers = {
    [M.COLLECT.BLOCK] = require("aru.agent.collect.block"),
    [M.COLLECT.DIAGNOSTIC] = require("aru.agent.collect.diagnostic"),
}

---@param ctx aru.agent.ConfigState
---@param names aru.agent.collect.Type[]
---@return aru.agent.payload.ContextItem[]
function M.resolve(ctx, names)
    ---@type aru.agent.payload.ContextItem[]
    local items = {}
    for _, name in ipairs(names) do
        local provider = providers[name]
        if not provider then
            log:error("Unknown collect provider: %s", name)
        else
            local item = provider.collect(ctx.state)
            if item then table.insert(items, item) end
        end
    end

    return items
end

return M
