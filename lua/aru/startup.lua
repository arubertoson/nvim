---@module 'aru.startup'
---
--- Startup loading and performance measurement
---
--- Loads critical Lua modules synchronously, then staggers deferred modules
--- one-by-one with a short delay. Deferred startup errors are collected and
--- reported once before runtime notifications are enabled.
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
        log:error(modname)
        return false, modname
    end

    local ok, err = pcall(require, modname)
    if not ok then return false, ("require error %s: %s"):format(modname, err) end
    return true
end

--- Schedules a single file after defer_delay_ms, then yields until completion.
--- Execution is synchronous per file; loads are staggered, not parallel.
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
---@param path string Absolute or relative path to a Lua file
local function must(path)
    local ok, err = load_file(path)
    if not ok then error(("critical module failed to load: %s"):format(err)) end
end

--- Loads groups sequentially; each group and file is processed in order.
--- Use for core config that must be available immediately.
---@param groups string[][] Ordered groups of file paths to load
function M.load_critical_paths(groups)
    for _, files in ipairs(groups) do
        for _, path in ipairs(files) do
            local _, elapsed = M.timeit_ms(function() must(path) end)
            log:trace(("loaded %s in %.3f ms"):format(path, elapsed))
        end
    end
end

--- Staggers loading across files using coroutine yield/resume so the UI
--- remains responsive between files. Execution per file is synchronous.
---@param groups string[][] Ordered groups of file paths to load
---@param defer_delay_ms? number Delay in ms between each file (default 2)
---@param on_finish? fun() Callback to run after all deferred files finish
function M.load_deferred_paths(groups, defer_delay_ms, on_finish)
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

        if on_finish then
            local ok, err = pcall(on_finish)
            if not ok then
                log:error(("deferred on_finish failed: %s"):format(err))
            end
        end
    end)()
end

local function flush_startup_errors()
    if #_errors == 0 then return end

    vim.notify("Deferred load errors:\n" .. table.concat(_errors, "\n"), vim.log.levels.ERROR)

    _errors = {}
end

--- Attach user-facing notifications after startup loading is complete.
local function attach_notify_sink()
    local ok, err = pcall(
        function()
            require("aru.log"):add({
                type = "notify",
                level = vim.log.levels.INFO,
            })
        end
    )
    if not ok then vim.notify("log notify sink attach failed:\n" .. err, vim.log.levels.ERROR) end
end

---@param critical string[][] Ordered groups of file paths to load
---@param deferred string[][]
function M.load(critical, deferred)
    -- Module loading with performance tracking
    --
    -- Everything is timed so I can see what's slow and replace it.
    -- The split between immediate and deferred loading creates the illusion
    -- of instant startup while still getting all features eventually.
    local _, total_time = M.timeit_ms(function()
        -- Immediate loading - critical path for UI responsiveness
        --
        -- These must load synchronously because I need them working immediately
        -- when the editor appears. The order matters for dependencies.
        local _, direct_load_time = M.timeit_ms(function() M.load_critical_paths(critical) end)
        log:trace(string.format("Critical path load time: %.3f ms", direct_load_time))

        -- Deferred loading - plugins
        --
        -- These load after 2ms delay to let UI render first. At this point order is
        -- not important, we just want everything... eventually.
        local _, defer_load_time = M.timeit_ms(function()
            M.load_deferred_paths(deferred, 2, function()
                -- Flush startup errors before enabling user-facing runtime logs.
                flush_startup_errors()
                attach_notify_sink()
            end)
        end)
        log:trace(string.format("Deferred load time: %.3f ms", defer_load_time))
    end)

    -- Performance summary
    --
    -- Total synchronous time here excludes the deferred work itself; that runs
    -- later through scheduled callbacks.
    log:trace(string.format("total load time: %.3f ms", total_time))
end

return M
