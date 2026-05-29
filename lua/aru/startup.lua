---@module 'aru.startup'
---
--- Core utilities for file loading and performance measurement
---
--- Utilities for loading Lua files and measuring performance in Neovim.
--- Supports immediate loading and deferred, staggered synchronous loading.
--- Deferred loading schedules files with a small delay and runs them
--- one-by-one (no parallel execution), reducing startup contention.
---
--- Features:
--- - Synchronous file loading with error handling and timing
--- - Deferred, staggered synchronous loading via vim.defer_fn + coroutines
--- - Simple function timing helper in milliseconds
--- - Structured logging to trace load times and failures
local log = require("aru.log")

local M = {}

local _errors = {}
local DEFER_DELAY_MS = 2

--- Check if the current environment is running on Windows Subsystem for Linux
---@return boolean
function M.is_wsl_shell()
    local release = vim.uv.os_uname().release
    return release:find("WSL", 1, true) ~= nil
end

--- Check if the current environment is running in a SSH shell
---@return boolean
function M.is_ssh_shell()
    return (vim.env.SSH_CLIENT ~= nil or vim.env.SSH_CONNECTION ~= nil or vim.env.SSH_TTY ~= nil)
end

--- Measures wall time using vim.uv.hrtime() and returns ms.
---
---@param fn fun(): any Function to time
---@return any result The function's return
---@return number time_ms Elapsed time in milliseconds (monotonic clock)
function M.timeit_ms(fn)
    local start = vim.uv.hrtime()
    local result = fn()
    local time = (vim.uv.hrtime() - start) / 1000000
    return result, time
end

---@return string
local function module_path(path)
    local mod = path:match("lua/(.+)%.lua$")
    return mod and mod:gsub("/", ".")
end

--- Loads and executes a Lua file immediately in the global environment.
--- Logs errors and traces load duration in milliseconds.
---
---@param path string Absolute or relative path to a Lua file
---@return boolean success True if the file was loaded successfully
---@return string|nil error Error message if the file failed to load
local function load_file(path)
    local modname = module_path(path)
    local ok, err = pcall(require, modname)
    if not ok then return false, ("require error %s: %s"):format(modname, err) end
    return true
end

--- Schedules a single file to run after defer_delay_ms, then yields
--- the caller coroutine until completion. Execution is still synchronous
--- per file; loads are staggered, not parallel.
---
---@param path string Path to a Lua file
---@param defer_delay_ms number Delay in ms before running the file
local function defer_load_file(path, defer_delay_ms)
    local co = coroutine.running()

    vim.defer_fn(function()
        local ok, errmsg = load_file(path)
        if not ok then
            log:error(errmsg)
            table.insert(_errors, ("%s: %s"):format(path, errmsg))
        end

        local ok_resume, errmsg = coroutine.resume(co)
        if not ok_resume then
            log:error(errmsg)
            table.insert(_errors, ("%s: %s"):format(path, errmsg))
        end
    end, defer_delay_ms)

    coroutine.yield()
end

--- Wraps the loading logic and errors on a failed load.
--- The critical path can't fail, if it does we should
--- stop execution and notify the user.
---
---@param path string Absolute or relative path to a Lua file
local function must(path)
    local ok, err = load_file(path)
    if not ok then error(("critical module failed to load: %s"):format(err)) end
end

--- Loads groups sequentially; each group and file is processed in order.
--- Use for core config that must be available immediately.
---
---@param groups string[][] Ordered groups of file paths to load
function M.load_files(groups)
    for _, files in ipairs(groups) do
        for _, path in ipairs(files) do
            local _, elapsed = M.timeit_ms(function() must(path) end)
            log:trace(("loaded %s in %.3f ms"):format(path, elapsed))
        end
    end
end

--- Staggers loading across files using coroutine yield/resume so the UI
--- remains responsive between files. Execution per file is synchronous.
---
---@param groups string[][] Ordered groups of file paths to load
---@param defer_delay_ms? number Delay in ms between each file (default 2)
function M.defer_load_files(groups, defer_delay_ms)
    if defer_delay_ms == nil then defer_delay_ms = DEFER_DELAY_MS end

    coroutine.wrap(function()
        for _, files in ipairs(groups) do
            for _, path in ipairs(files) do
                local _, elapsed = M.timeit_ms(
                    function() defer_load_file(path, defer_delay_ms) end
                )
                log:trace(("loaded %s in %.3f ms"):format(path, elapsed))
            end
        end
    end)()
end

--- During our startup execution, when we are working on deferred methods,
--- errors are collected instead of spamming the message log. When the
--- startup is complete, we flush the errors to the user.
function M.flush_startup_errors()
    if #_errors == 0 then return end

    vim.notify("Deferred load errors:\n" .. table.concat(_errors, "\n"), vim.log.levels.ERROR)
    _errors = {}
end

-- Create a global print function for debugging
_G.P = function(...)
    -- Inspect all arguments
    local objects = vim.tbl_map(vim.inspect, { ... })
    local lines = vim.split(table.concat(objects, "\n"), "\n")

    -- Create a true scratch buffer (unlisted, no file)
    local buf = vim.api.nvim_create_buf(false, true)

    -- Dump the lines into the buffer
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Set buffer options: wipe out when hidden, treat as Lua for syntax highlighting
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "lua"

    -- Open a vertical split and set the buffer
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
end

return M
