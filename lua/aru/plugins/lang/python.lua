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
		opts = { ensure_installed = { "ruff", "basedpyright" } },
	},

	{
		"neovim/nvim-lspconfig",
		optional = true,
		opts = {
			servers = {
				basedpyright = {
					enabled = true,
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
				ruff_lsp = {
					enabled = true,
					keys = {
						{
							"<leader>o",
							function()
								vim.lsp.buf.code_action({
									context = {
										diagnostics = vim.lsp.diagnostic.get_line_diagnostics(),
										only = { "source.organizeImports" },
									},
								})
							end,
						},
					},
				},
			},
		},
		-- setup = {
		-- 	[ruff] = function()
		--
		-- 	end
		-- }
		-- config = function(_, opts)
		-- 	local lspconfig = require("lspconfig")
		--
		-- 	local capabilities = nil
		-- 	if pcall(require, "cmp_nvim_lsp") then
		-- 		capabilities = require("cmp_nvim_lsp").default_capabilities()
		-- 	end
		--
		-- 	for name, config in pairs(opts.servers) do
		-- 		config = vim.tbl_deep_extend("force", {}, {
		-- 			capabilities = capabilities,
		-- 		}, config)
		--
		-- 		lspconfig[name].setup(config)
		-- 	end
		-- end,
	},
}
