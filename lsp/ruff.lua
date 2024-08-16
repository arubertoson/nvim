---@type vim.lsp.Config
return {
	cmd = { "ruff", "server" },
	filetypes = { "python" },
	root_markers = {
		"pyproject.toml",
		"setup.py",
		"setup.cfg",
		"requirements.txt",
		"Pipfile",
		"pyrightconfig.json",
		"ruff.toml",
		".ruff.toml",
		".git",
	},
	on_attach = function(client, _)
		client.server_capabilities.hoverProvider = false
	end,
	settings = {
		ruff = {
			single_file_support = true,
		},
	},
}
