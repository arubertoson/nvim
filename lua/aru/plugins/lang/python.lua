local python_ft = { "python" }

return {
	{
		"nvim-treesitter/nvim-treesitter",
		optional = true,
		opts = { ensure_installed = { "python", "ninja", "rst" } },
	},

	{
		"williamboman/mason.nvim",
		optional = true,
		opts = { ensure_installed = { "ruff", "ruff-lsp", "basedpyright" } },
	},

	{
		"neovim/nvim-lspconfig",
		optional = true,
		opts = {
			servers = {
				basedpyright = {
					settings = {
						basedpyright = {
							analysis = {
								typeCheckingMode = "standard",
							},
						},
					},
					on_attach = function(client, _)
						client.server_capabilities.documentFormattingProvider = false
						client.server_capabilities.documentRangeFormattingProvider = false
					end,
				},
				ruff_lsp = {},
			},
		},
	},
}
