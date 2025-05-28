local theme = {}

local aru = require("aru")
local helper = require("aru.helper")

local fmt = string.format
local cache = fmt("%s/nvim-theme", os.getenv("XDG_CACHE_HOME"))

function theme.cache()
	if vim.g.colors_name then
		vim.fn.writefile({ vim.g.colors_name }, cache)
	end
end

function theme.set(name)
	local ok, mod = pcall(require, name)
	if ok then
		aru.log:debug(fmt("Setting colorscheme: %s", name))

		vim.cmd(fmt("colorscheme %s", name))
	else
		aru.log:error(mod)
	end
end

local function isfile(path)
	local f = io.open(path, "r")
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

function theme.reload()
	local scheme = aru.theme
	if isfile(cache) then
		scheme = vim.fn.readfile(cache)[1] or aru.theme
	end

	aru.log:debug(fmt("reloading colorscheme: %s", scheme))

	theme.set(scheme)
end

function theme.setup()
	-- Make sure that we regen the user highlights after we update
	-- a theme
	helper.create_augroup("UserColorTheme", {
		{
			event = { "ColorScheme" },
			command = function()
				require("aru.config.theme").cache()
			end,
		},
	})

	vim.opt.termguicolors = true
	if not vim.g.colors_name then
		require("aru").log:debug("Reloading color shceme")

		theme.reload()
	end
end

return theme
