---@module "aru.agent.config"
local M = {}

---@alias aru.agent.config.FloatSide "left"|"right"

---@class aru.agent.config.FloatOpts
---@field side aru.agent.config.FloatSide
---@field width integer
---@field before_open fun(layout: aru.agent.config.FloatLayout)|nil
---@field after_close fun(layout: aru.agent.config.FloatLayout)|nil

---@class aru.agent.config.FloatLayout
---@field side aru.agent.config.FloatSide
---@field width integer

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
    float = {
        side = "right",
        width = 60,
    },
}

local config = vim.deepcopy(defaults)

function M.setup(opts)
    opts = opts or {}
    if
        opts.float
        and opts.float.side
        and opts.float.side ~= "left"
        and opts.float.side ~= "right"
    then
        error("agent float side must be 'left' or 'right'")
    end
    if
        opts.float
        and opts.float.width
        and (
            type(opts.float.width) ~= "number"
            or opts.float.width < 1
            or opts.float.width % 1 ~= 0
        )
    then
        error("agent float width must be a positive integer")
    end

    config = vim.tbl_deep_extend("force", config, opts)
end

function M.get() return config end

return M
