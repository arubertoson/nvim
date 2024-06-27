return {
	{ "rafcamlet/nvim-luapad", config = true },
	{
		"milanglacier/yarepl.nvim",
		event = "VeryLazy",
		config = function()
			require("yarepl").setup({
				wincmd = function(bufnr, _)
					vim.cmd([[belowright 15 split]])
					vim.api.nvim_set_current_buf(bufnr)
				end,
			})
			require("aru.utils").create_augroup("aru-repl-group", {
				{
					event = { "FileType" },
					pattern = {
						"python",
						"sh",
						"REPL",
					},
					command = function(args)
						local ft_to_repl = {
							python = "ipython",
							sh = "bash",
						}
						local repl = ft_to_repl[vim.bo.filetype]
						repl = repl and ("-" .. repl) or ""

						-- stylua: ignore
						require("aru.utils.keymaps").set_maps({
							{ { "n" }, "<localleader>rs", string.format("<Plug>(REPLStart%s)", repl), { desc = "Start an REPL", buffer = args.buffer }, },
							{ { "n" }, "<localleader>rf", "<Plug>(REPLFocus)", { desc = "Focus on REPL", buffer = args.buffer }, },
							{ { "n" }, "<localleader>rv", "<CMD>Telescope REPLShow<CR>", { desc = "View REPLs in telescope" }, buffer = args.buffer },
							{ { "n" }, "<localleader>rh", "<Plug>(REPLHide)", { desc = "Hide REPL", buffer = args.buffer} },
							{ { "v" }, "<localleader>f", "<Plug>(REPLSendVisual)", { desc = "Send visual region to REPL", buffer = args.buffer } },
							{ { "n" }, "<localleader>fs", "<Plug>(REPLSendLine)", { desc = "Send line to REPL", buffer = args.buffer } },
							{ { "n" }, "<localleader>f", "<Plug>(REPLSendOperator)", { desc = "Send current line to REPL", buffer = args.buffer } },
							{ { "n" }, "<localleader>re", "<Plug>(REPLExec)", { desc = "Execute command in REPL", expr = true, buffer = args.buffer } },
							{ { "n" }, "<localleader>rq", "<Plug>(REPLClose)", { desc = "Quit REPL", buffer = args.buffer } },
							{ { "n" }, "<localleader>rc", "<CMD>REPLCleanup<CR>", { desc = "Clear REPLs.", buffer = args.buffer} },
							{ { "n" }, "<localleader>rS", "<CMD>REPLSwap<CR>", { desc = "Swap REPLs.", buffer = args.buffer } },
							{ { "n" }, "<localleader>r?", "<Plug>(REPLStart)", { desc = "Start an REPL from available REPL metas", buffer = args.buffer } },
							{ { "n" }, "<localleader>ra", "<CMD>REPLAttachBufferToREPL<CR>", { desc = "Attach current buffer to a REPL", buffer = args.buffer } },
							{ { "n" }, "<localleader>rd", "<CMD>REPLDetachBufferToREPL<CR>", { desc = "Detach current buffer to any REPL", buffer = args.buffer } },
						})
					end,
				},
				{
					event = { "BufWinEnter" },
					command = function(args)
						if vim.bo.filetype ~= "REPL" then
							return
						end

						local colors = require("aru.utils.colors")
						local adjusted_bg = colors.get_adjusted_hl("Normal", 0.75)
						local winid = vim.api.nvim_get_current_win()

						vim.api.nvim_set_hl(0, "REPLDimmedBackground", { bg = adjusted_bg })
						-- For whatever reason this does not work without
						-- the defer.
						vim.defer_fn(function()
							vim.api.nvim_set_option_value(
								"winhighlight",
								"Normal:REPLDimmedBackground",
								{ scope = "local", win = winid }
							)
						end, 5)
					end,
				},
			})
		end,
	},
}
