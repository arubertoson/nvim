return {
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre", "BufReadPost", "InsertLeave" },
		cmd = "ConformInfo",
		lazy = true,
		keys = {
			{
				"<leader>bf",
				function()
					require("conform").format({ async = true, lsp_format = "never" })
				end,
				mode = { "n", "v" },
			},
			{
				"<leader>bF",
				function()
					require("conform").format({ formatters = { "injected" }, timeout_ms = 3000 })
				end,
				mode = { "n", "v" },
				desc = "Format Injected Langs",
			},
		},
		opts = {
			notify_on_error = false,
			format = {
				timeout_ms = 5000,
				async = false,
				quiet = false,
				lsp_format = "fallback",
			},
			format_on_save = function(_)
				return { timeout_ms = 5000, lsp_format = "fallback" }
			end,
			formatters_by_ft = {
				sh = { "shfmt" },
			},
			formatters = {
				injected = { options = { ignore_errors = true } },
			},
		},
		init = function()
			vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
		end,
	},
}
