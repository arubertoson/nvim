---@module "aru.agent.session"
---Tracks whether the last successful agent handoff can be continued with `pi -c`.

local runtime = require("aru.agent.runtime")

local M = {}

local continuable = false
local last_cwd = nil

---@return boolean
function M.can_continue()
    return continuable and last_cwd == vim.fn.getcwd()
end

---@param mode aru.agent.runtime.Mode|nil
---@param cwd string
function M.mark_success(mode, cwd)
    last_cwd = cwd
    mode = mode or runtime.MODE.NEW_SESSION

    if mode == runtime.MODE.ONE_SHOT or mode == runtime.MODE.PASTE then
        continuable = false
    else
        continuable = true
    end
end

return M
