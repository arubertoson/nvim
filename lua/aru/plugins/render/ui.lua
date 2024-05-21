return {
	-- git signs highlights text that has changed since the list
	-- git commit, and also lets you interactively stage & unstage
	-- hunks in a commit.
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufWritePre", "BufReadPost", "InsertLeave" },
		opts = {
			signs = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "▎" },
				untracked = { text = "▎" },
			},
		},
	},
	{
		-- "olivercederborg/poimandres.nvim",
		-- "aktersnurra/no-clown-fiesta.nvim",
		-- "rebelot/kanagawa.nvim",
		"rose-pine/neovim",
		lazy = false,
		priority = 1000,
		config = function()
			require("rose-pine").setup({})
		end,
		init = function()
			vim.cmd("colorscheme rose-pine")
		end,
	},
}
