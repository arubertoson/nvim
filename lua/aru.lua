--[[ aru

This modules sets up the aru namespace that will be used for configuration and
other functionality throughout this nvim configuration.

TODO: aru should only provide either configuration or simply act as a collection
Merging stuff to a "collected" namespace is confusing and not deliberate, I want most
of my decisions to be clear/readable and deliberate. Collecting everything for ease of use
is a double edged sword where it might be unclear where things come from. For now, this is
an acceptable compromise.

]]

-- Headless indicates that we are only performing install setup of necessary plugins.
local headless = os.getenv("ARU_HEADLESS_INSTALL")
if headless ~= nil then
	lazy = require("aru.lazy_init")
	lazy.setup({
		import = "aru/lazy/core",
		change_detection = { notify = false },
	})

	print("done setting things up")
	return
end

-- To avoid polluting the global namespace we are merging configuration and other
-- basic functionality.
-- local aru = require("aru.config")

-- Merge logger to namespace
log = require("aru.utils.logging").logger("INFO")

return {}
