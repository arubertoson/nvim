return {
	{
		"thesimonho/kanagawa-paper.nvim",
		lazy = false,
		priority = 1000,
		opts = {
			overrides = function()
				return {
					LspInlayHint = { fg = "#54546D", bg = "None", italic = true },
				}
			end,
			dim_inactive = true,
		},
	},
}
