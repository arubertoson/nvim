---@module "aru.log"
---
---Central logging facade for our Neovim configuration. It exposes a
---single entry point that multiplexes messages to sinks while honouring our
---bias toward minimal runtime dependencies and fast startup. Buffer sinks keep
---history inside Neovim for quick inspection, file sinks preserve long-lived
---traces, and notify sinks surface urgent issues in the UI.
---@class BasicSinkConfig
---@field type string Sink type: "file", "buffer", or "notify"
---@field level integer Sink-specific minimum log level

---@class FileSinkConfig : BasicSinkConfig
---@field path string|nil File path
---@field _file file*|nil

---@class BufferSinkConfig : BasicSinkConfig
---@field buffer integer|nil Buffer handle
---@field name string|nil buffer name

---@class NotifySinkConfig : BasicSinkConfig
---@field title string|nil Notification title
---@field format string|nil Notify-specific message format

---@alias SinkConfig FileSinkConfig|BufferSinkConfig|NotifySinkConfig

---@class LogConfig
---@field level integer|nil Default level for the implicit buffer sink only
---@field format string|nil Message format template
---@field sinks SinkConfig[]|nil Default sink type or sink config

local M = {}

---Default log buffer name used when no explicit sink is configured.
---A deterministic title makes it easy to pin the window and mirrors
---our preference for predictable workspace state over randomness.
local LOG_BUFFER_NAME = "aru.log"

---To prevent log buffer from growing without bound, we cap the number of
---lines at a constant given value.
local LOG_BUFFER_MAX_LINES = 1000

---Cache level name mappings to sidestep repeated table lookups.
---The log module frequently runs inside tight feedback loops where every
---allocation matters, so we hoist the mapping once and reuse it.
local LEVEL_NAMES = {
    [vim.log.levels.ERROR] = "ERROR",
    [vim.log.levels.WARN] = "WARN",
    [vim.log.levels.INFO] = "INFO",
    [vim.log.levels.DEBUG] = "DEBUG",
    [vim.log.levels.TRACE] = "TRACE",
}

---Global configuration shared across all logger instances.
---The level is only used for the implicit default buffer sink. Explicit sinks
---must declare their own level so routing is not affected by hidden global gates.
local DEFAULT_CONFIG = {
    level = vim.log.levels.INFO,
    format = "[{time}][{pid}][{level}][{module}:{linenr}] {msg}",
    sinks = {},
}

---Check if we're currently in a textlock. What that essentially means is that
---neovim is unable to perform any programmatic changes to the UI, such as
---redrawing or updating the statusline.
---@return boolean
local function in_textlock()
    if vim.in_fast_event() then return true end

    local m = vim.fn.mode()
    if m == "c" or m == "r" or m == "!" then return true end

    if vim.fn.getcmdwintype() ~= "" then return true end
    return false
end

-- simple queue for buffered log lines per bufnr
local queue = {}
local scheduled = false

local function flush()
    scheduled = false
    -- If we are in a textlock mode, we defer the flush and try again later.
    -- This let's us avoid causing issues when UI thread might be busy with
    -- other things.
    if in_textlock() then
        vim.defer_fn(function()
            if not scheduled then
                scheduled = true
                vim.schedule(flush)
            end
        end, 20)
        return
    end

    for bufnr, chunks in pairs(queue) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            local ok, err = pcall(function()
                vim.api.nvim_set_option_value(
                    "modifiable",
                    true,
                    { buf = bufnr }
                )
                for _, lines in ipairs(chunks) do
                    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
                end

                local cnt = vim.api.nvim_buf_line_count(bufnr)
                local max = LOG_BUFFER_MAX_LINES

                if cnt > max then
                    vim.api.nvim_buf_set_lines(bufnr, 0, cnt - max, false, {})
                end

                vim.api.nvim_set_option_value(
                    "modifiable",
                    false,
                    { buf = bufnr }
                )
                vim.api.nvim_set_option_value(
                    "modified",
                    false,
                    { buf = bufnr }
                )
            end)

            if not ok then
                error(("we need to handle this somehow: %s"):format(err))
                -- TODO: Find a better way to handle this
                -- This is a fallback to avoid a crash in the UI thread
            end
        end
        queue[bufnr] = nil
    end
end

local function queue_lines(bufnr, lines)
    if not queue[bufnr] then queue[bufnr] = {} end
    table.insert(queue[bufnr], lines)
    if not scheduled then
        scheduled = true
        vim.schedule(flush)
    end
end

---Return ISO-8601 timestamps with millisecond precision.
---We tap into `vim.uv.gettimeofday` when available to avoid Lua's coarse
---`os.time` resolution, mirroring our focus on troubleshooting headroom for
---asynchronous Neovim events.
---@return string iso_time
local function iso_time()
    local sec, usec
    if vim.uv and vim.uv.gettimeofday then
        local ok, a, b = pcall(vim.uv.gettimeofday)
        if ok then
            sec, usec = a, b
        end
    end

    local base = os.date("!%Y-%m-%dT%H:%M:%S", sec)
    return string.format("%s.%03dZ", base, math.floor((usec or 0) / 1000))
end

---Resolve caller module and line number for log records.
---Stack walking is bounded because this module controls invocation depth,
---a deliberate choice to keep the implementation predictable across LuaJIT
---versions while avoiding heavy debug libraries.
---@param level integer|nil Stack level hint
---@return string
---@return number
---@return number
local function caller_info(level)
    level = level or 5
    local info = debug.getinfo(level, "Sl")
    local base = vim.fs.basename(info.short_src)
    return base:gsub("%.lua$", ""), info.currentline, vim.uv.os_getpid()
end

---Render a log message using the module's format template.
---Interpolation keeps placeholders explicit so downstream sinks can trust the
---layout, matching our desire to debug by scanning raw logs without formatting
---surprises.
---@param log_str string
---@param msg string
---@param level integer
local function render(log_str, msg, level)
    local time = iso_time()
    local module, linenr, pid = caller_info()

    local parts = {
        msg = msg,
        level = LEVEL_NAMES[level],
        module = module,
        linenr = linenr,
        time = time,
        pid = pid,
    }

    return (
        log_str:gsub(
            "{(%w+)}",
            function(key)
                return parts[key] ~= nil and tostring(parts[key]) or ""
            end
        )
    )
end

---Create or reuse a dedicated log buffer sink.
---Buffers live inside Neovim so developers can inspect output without
---leaving the editor, aligning with the project's philosophy of tight
---feedback loops. The setup mirrors traditional scratch buffers while
---opting out of swap files to protect startup time.
---@param name string
---@return BufferSinkConfig
local function create_buffer_sink(name)
    local bufnr = nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if vim.endswith(buf_name, name) then
            bufnr = buf
            break
        end
    end

    if bufnr == nil then
        bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, name)
    end

    vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
    vim.api.nvim_set_option_value("filetype", "log", { buf = bufnr })
    vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
    vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
    vim.api.nvim_set_option_value("undolevels", -1, { buf = bufnr })
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

    -- XXX: Need to think about this a bit more.
    vim.api.nvim_buf_set_var(bufnr, "__bufdel_protected", true)

    return {
        type = "buffer",
        name = name,
        buffer = bufnr,
    }
end

---Create a file sink, ensuring directories exist without prompting.
---Log files persist beyond Neovim sessions so automation can scrape them,
---which explains the upfront directory creation and explicit line buffering
---for predictable flushing behaviour.
---@param path string
---@return FileSinkConfig
local function create_file_sink(path)
    local abs_path = vim.fs.abspath(vim.fs.normalize(path))

    local dirname = vim.fs.dirname(abs_path)
    if dirname and vim.fn.mkdir(dirname, "p") == 0 then
        error("Failed to create log directory: " .. dirname)
    elseif not dirname then
        error("Log path is invalid: " .. abs_path)
    end

    --@type file
    local f, err = io.open(abs_path, "a")
    if not f then error("Failed to create log file: " .. err) end

    f:setvbuf("line")

    return {
        type = "file",
        path = abs_path,
        _file = f,
    }
end

---@class Logger
---@field sinks SinkConfig[] List of configured output sinks
---@field format string Message format template
---@field _level integer Default level used only by the implicit buffer sink
local Logger = {}
Logger.__index = Logger

---Instantiate a logger with optional configuration overrides.
---The constructor biases toward a buffer sink so logs remain discoverable even
---before users tweak settings, a nod to sensible defaults in a shared config.
---@param config LogConfig
---@return Logger
function Logger:new(config)
    config = config or {}

    local merged = vim.tbl_extend("force", DEFAULT_CONFIG, config)
    self = setmetatable({
        _level = merged.level,
        format = merged.format,
        sinks = {},
    }, self)

    if next(merged.sinks) == nil then
        local buf_sink = create_buffer_sink(LOG_BUFFER_NAME)
        buf_sink.level = merged.level

        self.sinks = { buf_sink }
    else
        for _, sink in ipairs(merged.sinks) do
            self:add(sink)
        end
    end

    return self
end

---Update the logger's configuration in place, sinks are cleaned up
---and reapplied, level and format is updated if provided.
---@param config LogConfig
---@return Logger
function Logger:apply_config(config)
    for _, sink in ipairs(self.sinks) do
        if sink.type == "file" and sink._file then
            pcall(function()
                sink._file:flush()
                sink._file:close()
            end)
        elseif sink.type == "buffer" and sink.buffer then
            pcall(
                function()
                    vim.api.nvim_buf_delete(sink.buffer, { force = true })
                end
            )
        end
    end
    self.sinks = {}

    -- Apply the new config
    self._level = config.level or self._level
    self.format = config.format or self.format
    for _, sink in ipairs(config.sinks or {}) do
        self:add(sink)
    end

    return self
end

---Create a lightweight child logger that shares this logger's sinks but uses
---an explicit module label in formatted output.
---@param name string
---@return Logger
function Logger:bind(name)
    return setmetatable({
        _level = self._level,
        format = self.format:gsub("{module}", tostring(name)),
        sinks = self.sinks,
    }, Logger)
end

---Attach an additional sink to the logger.
---Each sink is materialised lazily to keep startup lean; this mirrors our
---tendency to defer work until a feature is explicitly requested.
---@param config SinkConfig
function Logger:add(config)
    if config.level == nil then
        error("Log sink requires explicit level: " .. vim.inspect(config))
    end

    local actions = {
        file = function() return create_file_sink(config.path) end,
        buffer = function()
            return create_buffer_sink(config.name or LOG_BUFFER_NAME)
        end,
        notify = function()
            return {
                type = "notify",
                title = config.title,
                format = config.format,
            }
        end,
    }
    local fn = actions[config.type]

    if not fn then error("Unknown sink type: " .. vim.inspect(config.type)) end

    local sink = fn()
    sink.level = config.level
    table.insert(self.sinks, sink)
end

---Send a message to a buffer sink.
---
---To maintain the `special` buffer we have to toggle a couple options
---before and after writing to it. We also maintain a max lines to prevent
---the buffer from growing without bound.
---@param bufnr integer
---@param msg string
local function emit_to_buffer(bufnr, msg)
    if not msg or msg == "" then return end

    local lines = vim.split(msg, "\n", { plain = true }) or { msg }
    queue_lines(bufnr, lines)
end

---Send a message to every sink that accepts the level.
---Filtering is sink-local: each configured sink declares exactly which minimum
---level it accepts, with no global cutoff hiding messages before routing.
---@param logger Logger
---@param level integer
---@param msg string
local function emit(logger, msg, level)
    local outstr = render(logger.format, msg, level)

    for _, sink in ipairs(logger.sinks) do
        if level >= sink.level then
            if sink.type == "file" then
                sink._file:write(outstr .. "\n")
            elseif sink.type == "buffer" then
                emit_to_buffer(sink.buffer, outstr)
            elseif sink.type == "notify" then
                local notify_format = sink.format or "[{level}] {module}:{linenr}\n{msg}"
                local notify_msg = render(notify_format, msg, level)
                vim.schedule(function()
                    vim.notify(notify_msg, level, { title = sink.title or "aru.log" })
                end)
            end
        end
    end
end

---Expose shorthand level methods to mirror `vim.notify` ergonomics.
---Users can call `log:info()` with minimal ceremony, which keeps incidental
---logging lightweight and reflects our preference for terse APIs.
for level, name in pairs(LEVEL_NAMES) do
    Logger[name:lower()] = function(self, msg, ...)
        if select("#", ...) > 0 then
            msg = msg:format(...)
        end
        emit(self, msg, level)
    end
end

-- Module singleton
local DEFAULT

---Reconfigure the default logger with a fresh sink layout.
---Existing resources are flushed and torn down to prevent file descriptor
---leaks or orphaned buffers, a discipline that keeps long-lived sessions tidy
---for us even across marathon editing sessions.
---@param config LogConfig
function M.configure(config)
    if DEFAULT then return DEFAULT:apply_config(config) end

    DEFAULT = Logger:new(config)
    return DEFAULT
end

M.Logger = Logger

local function require_default_or_error()
    if not DEFAULT then
        error(
            "Default logger is not configured. Call require('aru.log').configure(...) before use."
        )
    end
    return DEFAULT
end

return setmetatable(M, {
    __index = function(t, k)
        -- Cache and provide a shim for the default logger
        local f = function(_, ...)
            local d = require_default_or_error()
            local v = d[k]
            if type(v) == "function" then return v(d, ...) end
            return v
        end
        rawset(t, k, f)
        return f
    end,
})
