--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local config = {
	theme = "nightfox",
	modules = {
		"disable_builtin",
		"autocmds",
		"keymaps",
		"options",
		"plugin",
		-- "theme",
	},
	plugin_modules = {
		"core",
		"editor",
		"ui",
		"completion",
		"lsp",
	},
	log_level = "DEBUG",
}

config.log = require("aru.utils.logging").logger(config.log_level)

return config
