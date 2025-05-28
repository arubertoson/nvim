M = {}

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

function M.headless()
	require("lazy").setup({ import = "aru.modules.core" })

	print("done with initial setup.")
end

function M.setup()
	require("lazy").setup({
		{ import = "aru.plugins" },
		{ import = "aru.plugins.render" },
		{ import = "aru.plugins.navigation" },
		{ import = "aru.plugins.viewport" },
		{ import = "aru.plugins.lsp" },
		-- { import = "aru.plugins.lang" },
		-- { import = "aru.plugins.utils" },
	})
end

return M
