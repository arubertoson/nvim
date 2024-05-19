--
-- Arubertoson - The Neovim Settings
--
------------------------------------------------------------------------
vim.g.mapleader = ","
vim.g.maplocalleader = ";"

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

-- Lazy.setup({ "Tastyep/structlog.nvim" })
require("lazy").setup({ import = "custom/plugins" }, {
	change_detection = {
		notify = false,
	},
})
