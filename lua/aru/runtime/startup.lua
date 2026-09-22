---@module 'aru.runtime.startup'
---
--- Startup loading and performance measurement
---
--- Loads critical Lua modules synchronously, then staggers deferred modules
--- one-by-one with a short delay. Deferred startup errors are collected and
--- reported once when deferred loading completes.
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

---@class AruStartup.Group
---@field name string Human-readable group name used in startup logs.
---@field paths? string[] Ordered runtime paths in this group.
---@field setup? fun() Setup callback for a behavior with no local module to load.

---@class AruStartup.Config
---@field critical AruStartup.Group[]
---@field deferred AruStartup.Group[]

--- Measures wall time using vim.uv.hrtime() and returns ms.
---@param fn fun(): any Function to time
---@return any result The function's return
---@return number time_ms Elapsed time in milliseconds (monotonic clock)
function M.timeit_ms(fn)
    local start = vim.uv.hrtime()
    local result = fn()
    local time = (vim.uv.hrtime() - start) / 1000000
    return result, time
end

--- Extracts the module name from a path
---@param path string
---@return boolean, string|nil
local function module_path(path)
    local mod = path:match("lua/(.+)%.lua$")
    if not mod then return false, ("invalid lua runtime path: %s"):format(path) end
    return true, mod and mod:gsub("/", ".")
end

--- Requires the Lua module represented by a runtime file path.
---@param path string Absolute or relative path to a Lua file
---@return boolean success True if the file was loaded successfully
---@return string|nil error Error message if the file failed to load
local function load_file(path)
    local ok, modname = module_path(path)
    if not ok then
        log.error(modname)
        return false, modname
    end

    local ok, err = pcall(require, modname)
    if not ok then return false, ("require error %s: %s"):format(modname, err) end
    return true
end

---Runs an explicit behavior setup callback.
---@param setup fun()
---@return boolean success
---@return string? error
local function load_setup(setup)
    local ok, err = pcall(setup)
    if not ok then return false, ("setup error: %s"):format(err) end
    return true
end

---Schedules one startup task after defer_delay_ms, then yields until completion.
---@param group_name string Human-readable group name
---@param source string Path or task label used in logs
---@param load fun(): boolean, string|nil
---@param defer_delay_ms number Delay in ms before running the task
local function defer_load(group_name, source, load, defer_delay_ms)
    local co = coroutine.running()

    vim.defer_fn(function()
        local load_ok, load_err
        local _, elapsed = M.timeit_ms(function()
            load_ok, load_err = load()
        end)
        log.trace("Loaded deferred startup task", group_name, source, elapsed)

        if not load_ok then
            log.error(load_err)
            table.insert(_errors, ("%s: %s"):format(source, load_err))
        end

        local ok_resume, resume_err = coroutine.resume(co)
        if not ok_resume then
            log.error(resume_err)
            table.insert(_errors, ("%s: %s"):format(source, resume_err))
        end
    end, defer_delay_ms)

    coroutine.yield()
end

---@param source string
---@param load fun(): boolean, string|nil
local function must(source, load)
    local ok, err = load()
    if not ok then error(("critical startup task failed (%s): %s"):format(source, err)) end
end

--- Loads groups sequentially; each group and file is processed in order.
--- Use for core config that must be available immediately.
---@param groups AruStartup.Group[] Ordered groups of file paths to load
function M.load_critical_paths(groups)
    for _, group in ipairs(groups) do
        for _, path in ipairs(group.paths or {}) do
            local _, elapsed = M.timeit_ms(function()
                must(path, function() return load_file(path) end)
            end)
            log.trace("Loaded critical startup task", group.name, path, elapsed)
        end
        if group.setup then
            local _, elapsed = M.timeit_ms(function()
                must(group.name, function() return load_setup(group.setup) end)
            end)
            log.trace("Loaded critical startup task", group.name, "setup", elapsed)
        end
    end
end

--- Staggers loading across files using coroutine yield/resume so the UI
--- remains responsive between files. Execution per file is synchronous.
---@param groups AruStartup.Group[] Ordered groups of file paths to load
---@param defer_delay_ms? number Delay in ms between each file (default 2)
---@param on_finish? fun() Callback to run after all deferred files finish
function M.load_deferred_paths(groups, defer_delay_ms, on_finish)
    if defer_delay_ms == nil then defer_delay_ms = DEFER_DELAY_MS end

    coroutine.wrap(function()
        for _, group in ipairs(groups) do
            for _, path in ipairs(group.paths or {}) do
                defer_load(group.name, path, function() return load_file(path) end, defer_delay_ms)
            end
            if group.setup then
                defer_load(
                    group.name,
                    "setup",
                    function() return load_setup(group.setup) end,
                    defer_delay_ms
                )
            end
        end

        if on_finish then
            local ok, err = pcall(on_finish)
            if not ok then
                local errmsg = ("deferred on_finish failed: %s"):format(err)
                log.error(errmsg)
                table.insert(_errors, errmsg)
            end
        end
    end)()
end

local function flush_startup_errors()
    if #_errors == 0 then return end

    vim.notify("Deferred load errors:\n" .. table.concat(_errors, "\n"), vim.log.levels.ERROR)

    _errors = {}
end

M._test = {
    module_path = module_path,
    load_file = load_file,
    flush_startup_errors = flush_startup_errors,
    errors = function() return _errors end,
    reset = function() _errors = {} end,
}

---@param config AruStartup.Config
function M.load(config)
    local synchronous_start = vim.uv.hrtime()

    -- Immediate loading - critical path for UI responsiveness.
    local _, critical_time = M.timeit_ms(function() M.load_critical_paths(config.critical) end)
    log.trace(string.format("Critical startup completed in %.3f ms", critical_time))

    -- Deferred loading - ordered feature groups staggered so the UI can render.
    -- Individual timings measure module execution only. The phase timing includes
    -- stagger delays and event-loop scheduling through actual completion.
    local deferred_start = vim.uv.hrtime()
    M.load_deferred_paths(config.deferred, DEFER_DELAY_MS, function()
        local deferred_time = (vim.uv.hrtime() - deferred_start) / 1000000
        log.trace(string.format("Deferred startup completed in %.3f ms", deferred_time))
        flush_startup_errors()
    end)

    -- This excludes deferred work, which completes through scheduled callbacks.
    local synchronous_time = (vim.uv.hrtime() - synchronous_start) / 1000000
    log.trace(string.format("Synchronous startup completed in %.3f ms", synchronous_time))
end

return M
