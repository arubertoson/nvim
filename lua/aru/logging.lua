 local fmt = string.format
 local api = vim.api

 -- Define log levels and their numerical representation
 local levels = {
     DEBUG = 1,
     INFO = 2,
     WARN = 3,
     ERROR = 4,
     OFF = 5, -- Use OFF to disable all logging
 }

 -- Set the minimum log level to display
 -- Can be configured elsewhere if needed, e.g., based on environment variable
 local current_level = levels.DEBUG -- Default to DEBUG

 -- Function to get the current timestamp
 local function get_timestamp()
     local now = os.date("*t")
     return fmt("%02d:%02d:%02d", now.hour, now.min, now.sec)
 end

 -- Function to format the log message
 local function format_message(level_name, msg, ...)
     local timestamp = get_timestamp()
     local formatted_msg = fmt(msg, ...)
     -- Format: Timestamp [LEVEL] Message
     return fmt("%s [%s] %s", timestamp, level_name, formatted_msg)
 end

 -- Create the logger object
 local logger = {}

 --- Log a debug message
 ---@param msg string The message format string
 ---@vararg any Arguments for the format string
 function logger.debug(msg, ...)
     if current_level <= levels.DEBUG then
         local formatted = format_message("DEBUG", msg, ...)
         vim.notify(formatted, "info", { title = "ARU Debug" })
     end
 end

 --- Log an info message
 ---@param msg string The message format string
 ---@vararg any Arguments for the format string
 function logger.info(msg, ...)
     if current_level <= levels.INFO then
         local formatted = format_message("INFO", msg, ...)
         vim.notify(formatted, "info", { title = "ARU Info" })
     end
 end

 --- Log a warning message
 ---@param msg string The message format string
 ---@vararg any Arguments for the format string
 function logger.warn(msg, ...)
     if current_level <= levels.WARN then
         local formatted = format_message("WARN", msg, ...)
         vim.notify(formatted, "warn", { title = "ARU Warning" })
     end
 end

 --- Log an error message
 ---@param msg string The message format string
 ---@vararg any Arguments for the format string
 function logger.error(msg, ...)
     if current_level <= levels.ERROR then
         local formatted = format_message("ERROR", msg, ...)
         vim.notify(formatted, "error", { title = "ARU Error" })
     end
 end

 -- Optional: Function to set the log level dynamically
 ---@param level_name string The name of the level (e.g., "DEBUG", "INFO")
 function logger.set_level(level_name)
     local level = levels[string.upper(level_name)]
     if level then
         current_level = level
         logger.info("Log level set to %s", string.upper(level_name))
     else
         logger.warn("Invalid log level: %s. Keeping current level.", level_name)
     end
 end

 -- Return the logger object
 return logger
