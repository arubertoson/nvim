vim.lsp.config("basedpyright", {
	on_attach = function(client, _)
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
	end,
	settings = {
		basedpyright = {
			analysis = {
				typeCheckingMode = "standard",
				diagnosticMode = "workspace",
				-- ignore = { "*" },
			},
		},
	},
})

vim.lsp.config("ruff", {
	on_attach = function(client, _)
		client.server_capabilities.hoverProvider = false
	end,
	settings = {
		ruff = {
			single_file_support = true,
		},
	},
})

-- vim.lsp.config("ty", {
--   cmd = { 'ty', 'server' },
--   filetypes = { 'python' },
-- on_attach = function(client, _)
--     if client.server_capabilities.inlayHintProvider then
--         vim.lsp.inlay_hint.enable(true)
--     end
-- end,
--   root_markers = { 'ty.toml', 'pyproject.toml', '.git' },
-- }

vim.lsp.enable({ "basedpyright", "ruff" })
