---@module "aru.agent.config"
local M = {}

---@class aru.agent.config.ModeOpts
---@field session boolean

---@class aru.agent.config.Opts
---@field executable string
---@field session_dir string
---@field modes aru.agent.config.ModeOpts[]

local defaults = {
    executable = "pi-dev",
    session_dir = vim.fn.stdpath("cache") .. "/aru/agent/sessions",
    modes = {
        interactive = { session = true },
        one_shot = { session = false },
    },
}

local config = vim.deepcopy(defaults)

function M.setup(opts) 
    config = vim.tbl_deep_extend("force", defaults, opts or {})
end

function M.get() 
    return config
end

return M
