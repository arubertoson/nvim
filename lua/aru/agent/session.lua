---@module "aru.agent.session"
---Tracks whether the last successful agent handoff can be continued with `pi -c`.

local runtime = require("aru.agent.runtime")

local M = {}

local continuable = false
local last_cwd = nil

---@return boolean
function M.can_continue() return continuable and last_cwd == vim.fn.getcwd() end

---@param policy aru.agent.runtime.SessionPolicy|nil
---@param cwd string
function M.mark_success(policy, cwd)
    if policy ~= runtime.SESSION.NEW and policy ~= runtime.SESSION.CONTINUE then return end

    last_cwd = cwd
    continuable = true
end

return M
