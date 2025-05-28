local theme = {}

local helper = require("aru.helper")
local log = require("aru.logging").get_logger("AruTheme", "INFO") -- Explicitly set logger name and level

local fmt = string.format
local default_colorscheme = "kanagawa-paper-ink" -- Define a default colorscheme
local cache = fmt("%s/nvim-theme", os.getenv("XDG_CACHE_HOME"))

function theme.cache()
	if vim.g.colors_name then
		vim.fn.writefile({ vim.g.colors_name }, cache)
	end
end

function theme.set(name)
	log:debug(fmt("Attempting to set colorscheme: %s", name))
	local ok, err = pcall(vim.cmd, fmt("colorscheme %s", name))
	if not ok then
		log:error(fmt("Failed to set colorscheme %s: %s", name, err))
	else
		-- Success is implicit if no error. The ColorScheme autocommand handles caching.
		-- log:info(fmt("Successfully set colorscheme: %s", name))
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
	local scheme_name = default_colorscheme
	if isfile(cache) then
		local cached_scheme = vim.fn.readfile(cache)
		if cached_scheme and #cached_scheme > 0 and cached_scheme[1] ~= "" then
			scheme_name = cached_scheme[1]
		end
	end

	log:debug(fmt("reloading colorscheme: %s", scheme_name))

	theme.set(scheme_name)
end

function theme.setup()
	-- Make sure that we regen the user highlights after we update
	-- a theme
	helper.create_augroup("UserColorTheme", {
		{
			event = { "ColorScheme" },
			command = function()
				theme.cache() -- Call the cache function defined in this module
			end,
		},
	})

	vim.opt.termguicolors = true

	-- Defer the initial theme loading to VimEnter to ensure plugins are loaded
	helper.create_augroup("AruThemeLoader", {
		{
			event = { "VimEnter" },
			command = function()
				if not vim.g.colors_name then -- Check if a colorscheme is already set (e.g. by session or other plugin)
					log:debug(
						"VimEnter: No colorscheme set, attempting to load initial color scheme."
					)
					theme.reload()
				else
					log:debug(
						fmt(
							"VimEnter: Colorscheme '%s' already set, skipping initial load.",
							vim.g.colors_name
						)
					)
				end
			end,
			once = true, -- Important: run only once
			nested = true, -- Allow nested autocommands if theme.reload() triggers any
		},
	})
end

return theme
