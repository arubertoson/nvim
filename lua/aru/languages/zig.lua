---@brief
--- https://github.com/zigtools/zls
---
--- Zig LSP implementation + Zig Language Server
---
---@type vim.lsp.Config
vim.lsp.config("zls", {
	cmd = { "zls" },
	filetypes = { "zig", "zir" },
	root_markers = { "zls.json", "build.zig", ".git" },
	workspace_required = false,
	-- https://github.com/zigtools/zls/blob/master/src/Config.zig
	settings = {
		zls = {
			-- enable_build_on_save = true,
			inlay_hints_hide_redundant_param_names = true,
			inlay_hints_hide_redundant_param_names_last_token = true,
			warn_style = true,
			highlight_global_var_declarations = true,
		},
	},
})

vim.lsp.enable("zls")
