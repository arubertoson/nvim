return {
	{ "nvim-lua/plenary.nvim" },
	{ "Tastyep/structlog.nvim", lazy = true },

	{
		"max397574/better-escape.nvim",
		config = function()
			require("better_escape").setup({
				mapping = { "jk", "kj" },
				clear_empty_lines = true,
				keys = "<Esc>",
			})
		end,
	},

	{
		"ojroques/nvim-bufdel",
		cmd = "BufDel",
		setup = function()
			require("aru.utils.keymaps").set({
				"n",
				"<localleader>q",
				":<C-u>BufDel<CR>",
				{ desc = "Delete Buffer Buffer" },
			})
		end,
	},

	{ "rmagatti/auto-session" },
}
