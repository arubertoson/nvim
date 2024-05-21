--
-- Arubertoson - The Neovim Settings
--
------------------------------------------------------------------------
vim.g.mapleader = ","
vim.g.maplocalleader = ";"

local imp_ok, _ = pcall(require, "aru.utils.logging")
if not imp_ok then
	print("logging module wasn't setup correctly, or this is the first run.")
end

require("aru")
