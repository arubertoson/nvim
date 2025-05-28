-- FIX: Rething logging library
-- a good alternative might be plenary, we are using an external package either way so might as well
-- use something that is "standardized" across many modules

local logging = {}

local fmt = string.format

function logging.logger(level)
	local struct_path = vim.fn.stdpath("data") .. "/lazy/structlog.nvim"

	---@diagnostic disable-next-line: undefined-field
	vim.opt.rtp:prepend(struct_path)

	local ok, structlog = pcall(require, "structlog")
	if not ok then
		vim.notify(fmt("structlog require error: %s", structlog)({ silent = true }))

		return
	end

	structlog.configure({
		file = {
			pipelines = {
				{
					level = structlog.level[level],
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
					sink = structlog.sinks.File(vim.fn.stdpath("config") .. "/nvim-config.log"),
				},
			},
		},
	})

	-- We don't need to perform any special checks here, the file is defined a couple of lines
	-- above.
	local log = structlog.get_logger("file")

	---@diagnostic disable-next-line: need-check-nil
	log:debug(fmt("%s logger merged with bootstrap namespace", log.name))

	return log
end

return logging
