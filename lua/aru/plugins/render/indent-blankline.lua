return {
	{
		"lukas-reineke/indent-blankline.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-treesitter",
		},
		main = "ibl",
		opts = {
			enabled = true,
			indent = {
				char = "╏",
				tab_char = { "", "╏" },
			},
			scope = {
				enabled = false,
			},
			-- exclude = {
			-- 	filetypes = {}
			-- 	buftypes = {}
			-- }
		},
	},
}
