--
-- Arubertoson - The Neovim Settings
--
------------------------------------------------------------------------

vim.g.mapleader = " "
vim.g.maplocalleader = ";"

function R(name)
	-- Some modules that needs to be initialized might not have a setup,
	-- requiring those will be enough and we can safely return afterwards.
	local mod = require(name)
	if type(mod) ~= "boolean" and type(mod["setup"]) == "function" then
		return require(name).setup()
	end
end

------------------------------------------------------------------------
-- Setup Headless
------------------------------------------------------------------------

-- Headless indicates that we are only performing install setup of necessary
-- plugins.
local headless = os.getenv("ARU_HEADLESS_INSTALL")
if headless ~= nil then
	require("aru.config.plugin").headless()

	return
end

------------------------------------------------------------------------
-- Setup Configuration Modules
------------------------------------------------------------------------

local fmt = string.format
local aru = require("aru")

aru.log:info("initializing neovim aru configuration")

for _, mod in ipairs(aru.modules) do
	aru.log:debug(fmt("loading module: %s", mod))

	R(fmt("aru.config.%s", mod))
end

aru.log:info("Done setting up aru configuration")
