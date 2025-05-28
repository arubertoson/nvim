return {
	{
		"stevearc/conform.nvim",
		opts = {
			format_on_save = {
				-- I recommend these options. See :help conform.format for details.
				lsp_format = "fallback",
				timeout_ms = 500,
			},
			formatters_by_ft = {
				lua = { "stylua" },
			},
		},
	},
}
