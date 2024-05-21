--[[ aru

This modules sets up the aru namespace that will be used for configuration and
other functionality throughout this nvim configuration.

TODO: aru should only provide either configuration or simply act as a collection
Merging stuff to a "collected" namespace is confusing and not deliberate, I want most
of my decisions to be clear/readable and deliberate. Collecting everything for ease of use
is a double edged sword where it might be unclear where things come from. For now, this is
an acceptable compromise.

]]

-- To avoid polluting the global namespace we are merging configuration and other
-- basic functionality, such as logging.
local aru = require("aru.config")

aru.log:debug("done setting up aru configuration")

return aru
