local conform = require("conform")

conform.setup({
	formatters_by_ft = {
		lua = { "stylua" },
		javascript = { "prettier" },
		javascriptreact = { "prettier" },
		typescript = { "prettier" },
		typescriptreact = { "prettier" },
		html = { "prettier" },
		markdown = { "prettier" },
		css = { "prettier" },
		scss = { "prettier" },
		json = { "prettier" },
		yaml = { "prettier" },
		python = { "ruff" },
        zig = { "zigfmt" },
		["*"] = { "trim_whitespace" },
	},
	-- Format on save
	-- format_on_save = function(bufnr)
	-- 	-- Disable with a global or buffer-local variable
	-- 	if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
	-- 		return
	-- 	end
	--
	-- 	return {
	-- 		timeout_ms = 500,
	-- 		lsp_fallback = true, -- Use LSP if no formatter configured
	-- 	}
	-- end,

	notify_on_error = true,
})

vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
vim.keymap.set("n", "<leader>lf", function()
	require("conform").format({ async = true, lsp_fallback = true })
end, { desc = "Format file" })
