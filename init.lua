--
-- Arubertoson - The Neovim Settings
--
------------------------------------------------------------------------

vim.g.mapleader = ";"
vim.g.maplocalleader = ","

------------------------------------------------------------------------
-- Lazy Setup
------------------------------------------------------------------------

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end

-- Add lazy to the `runtimepath`, this allows us to `require` it.
---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

local fmt = string.format
local logging_module = require("aru.logging")
local log = logging_module.get_logger("INFO") -- Or "DEBUG", "WARN", "ERROR" as needed

log:info("Trying to setup env.")

require("lazy").setup({
	{ import = "aru-custom" },
	{ import = "aru-editor" },
	{ import = "aru-viewport" },
	{ import = "aru-lsp" },
})

-- Setup the theme explicitly
-- The theme.setup() function itself defers actual colorscheme application to VimEnter
local theme_ok, theme_mod = pcall(require, "aru.theme")
if theme_ok then
	theme_mod.setup()
else
	log:error("Failed to load aru.theme: " .. tostring(theme_mod))
end

-- find files
-- git files
-- help tags
-- grep files
-- fuzzy grep current file
-- grep string
-- config files
-- symbols in file
-- symbols in workspace

vim.schedule(function()
	log:info("Done setting up aru configuration")
end)
