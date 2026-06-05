---@module 'spec'
---This file is used to define what plugins we need to fetch. The builtint
---pack handles downloading and calling packadd making the plugins available
---to require.
---
---We are also ensuring that we don't use load (to source plugin/ location)
---and to autoconfirm.

--- XXX: Check out:
--- - obsidian.nvim
--- - zk (zettelkasten)
---

vim.pack.add({
	-- ===========================================================================
	-- Libs
	-- ===========================================================================
	{
		src = "https://github.com/nvim-lua/plenary.nvim.git",
		version = "master",
	},
	{
		src = "https://github.com/nvim-tree/nvim-web-devicons",
		version = "master",
	},
	{
		src = "https://github.com/nvim-treesitter/nvim-treesitter",
		version = "main",
	},
	{
		src = "https://github.com/nvim-treesitter/nvim-treesitter-textobjects",
		version = "main",
	},

	{ src = "https://github.com/niba/continue.nvim", version = "main" },
	-- ===========================================================================
	-- Themes
	-- ===========================================================================
	{ src = "https://github.com/thesimonho/kanagawa-paper.nvim" },
	{ src = "https://github.com/rebelot/kanagawa.nvim" },

	-- UI Stuff
	{
		src = "https://github.com/lewis6991/gitsigns.nvim",
		version = vim.version.range("2.1.0"),
	},
	{
		src = "https://github.com/lukas-reineke/indent-blankline.nvim",
		version = vim.version.range("3.9.1"),
	},
	{
		src = "https://github.com/shortcuts/no-neck-pain.nvim",
		version = vim.version.range("2.5.3"),
	},
	{
		src = "https://github.com/stevearc/oil.nvim",
		version = vim.version.range("2.16.0"),
	},

	{
		src = "https://github.com/nvim-mini/mini.nvim",
		version = vim.version.range("0.17.0"),
	},

	-- ===========================================================================
	-- LSP / Formatting
	-- ===========================================================================
	{
		src = "https://github.com/stevearc/conform.nvim",
		version = vim.version.range("9.1.0"),
	},

	-- ===========================================================================
	-- Completion
	-- ===========================================================================
	{
		src = "https://github.com/Saghen/blink.cmp",
		version = vim.version.range("1.10.2"),
	},
	{
		src = "https://github.com/supermaven-inc/supermaven-nvim.git",
		version = "main",
	},

	-- ===========================================================================
	-- Navigation
	-- ===========================================================================
	{
		src = "file:////home/macke/dev/home/github.com/ThePrimeagen/harpoon",
		version = "harpoon2",
	}, -- Should point to local!

    -- ===========================================================================
    -- In Testing
    -- ===========================================================================

	{ src = "https://github.com/ibhagwan/fzf-lua", version = "main" },
	{ src = "https://github.com/andymass/vim-matchup" },
	{ src = "https://github.com/tpope/vim-sleuth" },
}, {
	load = false,
	confirm = false,
})
