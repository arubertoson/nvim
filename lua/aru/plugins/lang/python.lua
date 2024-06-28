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
		opts = { ensure_installed = { "ruff", "ruff-lsp", "basedpyright", "pyright", "python-lsp-server" } },
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
						client.server_capabilities.documentFormattingProvider = false
						client.server_capabilities.documentRangeFormattingProvider = false
						client.server_capabilities.completionProvider = false
					end,
				},
				pylsp = {
					settings = {
						pylsp = {
							plugins = {
								flake8 = { enabled = false },
								mccabe = { enabled = false },
								pycodestyle = { enabled = false },
								yapf = { enabled = false },
								pyflakes = { enabled = false },
								pylint = { enabled = false },
								autopep8 = { enabled = false },
							},
						},
					},
				},
				ruff_lsp = {
					-- If we don't have a valid file, ruff_lsp can't operate
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
