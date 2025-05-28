local M = {} -- Module to be returned

local fmt = string.format
local api = vim.api -- Not used in this version, but kept if needed later

-- Define log levels and their numerical representation
local levels = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    OFF = 5, -- Use OFF to disable all logging
}

-- Function to get the current timestamp
local function get_timestamp()
    local now = os.date("*t")
    return fmt("%02d:%02d:%02d", now.hour, now.min, now.sec)
end

-- Function to format the log message
local function format_message(level_name_str, msg_format, ...)
    local timestamp = get_timestamp()
    local formatted_msg_content = fmt(msg_format, ...)
    -- Format: Timestamp [LEVEL] Message
    return fmt("%s [%s] %s", timestamp, level_name_str, formatted_msg_content)
end

-- Metatable for logger instances
local logger_mt = {}
logger_mt.__index = logger_mt

--- Log a debug message
---@param self table The logger instance
---@param msg string The message format string
---@vararg any Arguments for the format string
function logger_mt:debug(msg, ...)
    if self.current_level <= levels.DEBUG then
        local formatted = format_message("DEBUG", msg, ...)
        vim.notify(formatted, vim.log.levels.INFO, { title = self.logger_name .. " Debug" })
    end
end

--- Log an info message
---@param self table The logger instance
---@param msg string The message format string
---@vararg any Arguments for the format string
function logger_mt:info(msg, ...)
    if self.current_level <= levels.INFO then
        local formatted = format_message("INFO", msg, ...)
        vim.notify(formatted, vim.log.levels.INFO, { title = self.logger_name .. " Info" })
    end
end

--- Log a warning message
---@param self table The logger instance
---@param msg string The message format string
---@vararg any Arguments for the format string
function logger_mt:warn(msg, ...)
    if self.current_level <= levels.WARN then
        local formatted = format_message("WARN", msg, ...)
        vim.notify(formatted, vim.log.levels.WARN, { title = self.logger_name .. " Warning" })
    end
end

--- Log an error message
---@param self table The logger instance
---@param msg string The message format string
---@vararg any Arguments for the format string
function logger_mt:error(msg, ...)
    if self.current_level <= levels.ERROR then
        local formatted = format_message("ERROR", msg, ...)
        vim.notify(formatted, vim.log.levels.ERROR, { title = self.logger_name .. " Error" })
    end
end

--- Set the log level for this logger instance dynamically
---@param self table The logger instance
---@param level_name string The name of the level (e.g., "DEBUG", "INFO")
function logger_mt:set_level(level_name)
    local upper_level_name = string.upper(level_name)
    local level_val = levels[upper_level_name]

    if level_val then
        self.current_level = level_val
        self.level_name = upper_level_name -- Store the name as well
        -- This :info message respects the new log level
        self:info("Log level set to %s", upper_level_name)
    else
        -- This warning should ideally always be visible, so use direct notify.
        local err_msg = fmt("Invalid log level: %s. Current level (%s) remains unchanged.", level_name, self.level_name)
        local formatted_err_msg = format_message("WARN", err_msg) -- No varargs for err_msg
        vim.notify(formatted_err_msg, "warn", { title = "ARU Warning" })
    end
end

--- Returns a new logger instance.
---@param logger_name_or_level string | nil Either the logger name or a log level string.
---@param explicit_level_name string | nil If provided, this is the log level string.
function M.get_logger(logger_name_or_level, explicit_level_name)
    local final_logger_name
    local final_level_name_str

    if explicit_level_name then
        -- Both arguments provided: logger_name_or_level is logger_name, explicit_level_name is level
        final_logger_name = logger_name_or_level or "ARU" -- Default name if first arg is nil
        final_level_name_str = explicit_level_name
    else
        -- Only one argument provided (or zero)
        if type(logger_name_or_level) == "string" and levels[string.upper(logger_name_or_level)] then
            -- Single argument is a valid level name
            final_logger_name = "ARU" -- Default logger name
            final_level_name_str = logger_name_or_level
        else
            -- Single argument is intended as a logger name (or nil)
            final_logger_name = logger_name_or_level or "ARU" -- Default name if nil
            final_level_name_str = "INFO" -- Default level
        end
    end

    -- Ensure final_level_name_str is defaulted if it ended up nil (e.g. get_logger(nil, nil))
    final_level_name_str = final_level_name_str or "INFO"
    local upper_final_level_name = string.upper(final_level_name_str)
    local initial_level_val = levels[upper_final_level_name]

    if not initial_level_val then
        -- Fallback for invalid level_name_str
        local err_msg = fmt("Invalid initial log level: %s. Defaulting to INFO.", final_level_name_str)
        -- Use a generic title for this setup warning, as logger name might be part of the issue
        local formatted_err_msg = format_message("WARN", err_msg)
        vim.notify(formatted_err_msg, vim.log.levels.WARN, { title = "Logging Setup Warning" })

        upper_final_level_name = "INFO"
        initial_level_val = levels.INFO
    end

    local new_logger = {
        logger_name = final_logger_name,
        current_level = initial_level_val,
        level_name = upper_final_level_name, -- Store the string name of the level for reference
    }
    return setmetatable(new_logger, logger_mt)
end

return M
