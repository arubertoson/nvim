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

	"projekt0n/github-nvim-theme",
	"rose-pine/neovim",
	"slugbyte/lackluster.nvim",
	"aktersnurra/no-clown-fiesta.nvim",

	{
		"rebelot/kanagawa.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("kanagawa").setup({
				dimInactive = true,
				theme = "wave",
				background = {
					dark = "wave",
					light = "lotus",
				},
			})
		end,
		init = function()
			vim.cmd("colorscheme kanagawa")
		end,
	},
}
