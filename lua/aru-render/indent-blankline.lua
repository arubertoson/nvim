return {
	{
		"lukas-reineke/indent-blankline.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-treesitter",
		},
		main = "ibl",
		init = function()
			local colors = require("aru.utils.colors")

			local adjusted_bg = colors.get_adjusted_hl("Normal", 1.3)

			vim.api.nvim_set_hl(0, "IBLIndent", { fg = adjusted_bg })
		end,
		opts = {
			enabled = true,
			indent = {
				char = "╏",
				highlight = { "IBLIndent" },
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
