---@module "aru.agent.config"
local M = {}

---@class aru.agent.config.FloatOpts
---@field before_open fun()|nil
---@field after_close fun()|nil

---@class aru.agent.config.Opts
---@field executable string
---@field runtime string
---@field session_dir string
---@field target_window_name string
---@field float aru.agent.config.FloatOpts

local defaults = {
    executable = "pi-dev",
    runtime = "pi",
    session_dir = vim.fn.stdpath("cache") .. "/aru/agent/sessions",
    target_window_name = "agent",
    float = {},
}

local config = vim.deepcopy(defaults)

function M.setup(opts) config = vim.tbl_deep_extend("force", config, opts or {}) end

function M.get() return config end

return M
