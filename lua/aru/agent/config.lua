---@module "aru.agent.config"
local M = {}

---@alias aru.agent.config.FloatSide "left"|"right"

---@class aru.agent.config.FloatOpts
---@field side aru.agent.config.FloatSide|nil
---@field width integer|nil
---@field before_open fun(layout: aru.agent.config.FloatLayout)|nil
---@field after_close fun(layout: aru.agent.config.FloatLayout)|nil

---@class aru.agent.config.FloatConfig
---@field side aru.agent.config.FloatSide
---@field width integer
---@field before_open fun(layout: aru.agent.config.FloatLayout)|nil
---@field after_close fun(layout: aru.agent.config.FloatLayout)|nil

---@class aru.agent.config.FloatLayout
---@field side aru.agent.config.FloatSide
---@field width integer

---@class aru.agent.config.Opts
---@field executable string|nil
---@field runtime string|nil
---@field session_dir string|nil
---@field target_window_name string|nil
---@field float aru.agent.config.FloatOpts|nil

---@class aru.agent.config.Config
---@field executable string
---@field runtime string
---@field session_dir string
---@field target_window_name string
---@field float aru.agent.config.FloatConfig

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

---@type aru.agent.config.Config
local config = vim.deepcopy(defaults)

local CONFIG_KEYS = {
    executable = true,
    runtime = true,
    session_dir = true,
    target_window_name = true,
    float = true,
}

local FLOAT_KEYS = {
    side = true,
    width = true,
    before_open = true,
    after_close = true,
}

---@param value table
---@param allowed table<string, boolean>
---@param name string
local function validate_keys(value, allowed, name)
    for key in pairs(value) do
        if not allowed[key] then error(("unknown %s option: %s"):format(name, tostring(key))) end
    end
end

---@param value any
---@param name string
local function validate_nonempty_string(value, name)
    if type(value) ~= "string" or value == "" then error(name .. " must be a non-empty string") end
end

---@param opts aru.agent.config.Opts|nil
function M.setup(opts)
    if opts == nil then return end
    if type(opts) ~= "table" then error("agent config must be a table") end
    validate_keys(opts, CONFIG_KEYS, "agent config")

    for _, name in ipairs({ "executable", "runtime", "session_dir", "target_window_name" }) do
        if opts[name] ~= nil then validate_nonempty_string(opts[name], "agent " .. name) end
    end

    if opts.float ~= nil then
        if type(opts.float) ~= "table" then error("agent float config must be a table") end
        validate_keys(opts.float, FLOAT_KEYS, "agent float")

        if opts.float.side ~= nil and opts.float.side ~= "left" and opts.float.side ~= "right" then
            error("agent float side must be 'left' or 'right'")
        end
        if
            opts.float.width ~= nil
            and (
                type(opts.float.width) ~= "number"
                or opts.float.width < 1
                or opts.float.width % 1 ~= 0
            )
        then
            error("agent float width must be a positive integer")
        end
        for _, name in ipairs({ "before_open", "after_close" }) do
            if opts.float[name] ~= nil and type(opts.float[name]) ~= "function" then
                error("agent float " .. name .. " must be a function")
            end
        end
    end

    config = vim.tbl_deep_extend("force", config, opts)
end

---@return aru.agent.config.Config
function M.get() return config end

return M
