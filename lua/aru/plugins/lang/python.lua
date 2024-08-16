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
							disableOrganizeImports = true,
						},
					},
					on_attach = function(client, _)
						-- Disable formatting capabilities in BasedPyright since Ruff handles that
						client.server_capabilities.documentFormattingProvider = false
						client.server_capabilities.documentRangeFormattingProvider = false
						-- Keep completion and other type-related features
					end,
				},
				ruff_lsp = {
					on_init = function(client, _)
						local bufnr = vim.api.nvim_get_current_buf()
						local name = vim.api.nvim_buf_get_name(bufnr)
						if name == "" then
							client.stop()
						end
					end,
					on_attach = function(client, _)
						local bufnr = vim.api.nvim_get_current_buf()
						local name = vim.api.nvim_buf_get_name(bufnr)
						if name == "" then
							client.stop()
						end
					end,
				},
			},
		},
	},
}
