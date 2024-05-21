-- FIX: Rething logging library
-- a good alternative might be plenary, we are using an external package either way so might as well
-- use something that is "standardized" across many modules

local logging = {}

local fmt = string.format

function logging.logger(level)

	local struct_path = vim.fn.stdpath("data") .. "/lazy/structlog.nvim"

	vim.opt.rtp:prepend(struct_path)

	-- print(vim.inspect(vim.opt.packpath))

	-- Struclog is self managed
	-- vim.cmd("packadd structlog.nvim")

	local ok, structlog = pcall(require, "structlog")
	if not ok then
		vim.notify(fmt("structlog require error: %s", structlog)({ silent = true }))

		return
	end

	local log_level = structlog.level[level]

	structlog.configure({
		file = {
			pipelines = {
				{
					level = log_level,
					processors = {
						structlog.processors.StackWriter(
							{ "line", "file" },
							{ max_parents = 3 }
						),
						structlog.processors.Timestamper("%H:%M:%S"),
					},
					formatter = structlog.formatters.Format(
						"%s [%s] %s: %-30s",
						{ "timestamp", "level", "logger_name", "msg" }
					),
					sink = structlog.sinks.File("./nvim-config.log")
				}
			}
		}
	})

	local log = structlog.get_logger("file")

	log:debug(fmt("%s logger merged with bootstrap namespace", log.name))

	return log
end

return logging
