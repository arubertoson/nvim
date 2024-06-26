return {
	{
		"nvim-focus/focus.nvim",
		version = "*",
		lazy = true,
		init = function()
			local fmt = string.format

			for _, char in ipairs({ "h", "j", "k", "l" }) do
				require("aru.utils.keymaps").set_maps({
					-- Jump to a window navigation
					{
						"n",
						fmt("<C-%s>", char),
						function()
							require("focus").split_command(char)
						end,
						{ silent = true },
					},
					-- Jump to window navigation including terminal
					{
						"t",
						fmt("<C-%s>", char),
						function()
							-- Don't have to check if buffer is a terminal or not,
							-- mapping will only be in effect in terminal buffers.
							if char == "h" or char == "l" then
								if vim.fn.winnr() == vim.fn.winnr(char) then
									return
								end
							end

							require("focus").split_command(char)
						end,
						{ silent = true },
					},
				})
			end
		end,
		config = function()
			local focus = require("focus")

			-- Certain focus functins should not work on specific file- and buffer
			-- types. Navigation and resizing when using these will mess the layout
			-- up.
			local ignore_filetypes = { "dbui", "dbout" }
			local ignore_buftypes = { "nofile", "prompt", "popup" }

			require("aru.utils").create_augroup("WinDisableResize", {
				{
					event = { "WinEnter" },
					command = function(_)
						if vim.tbl_contains(ignore_buftypes, vim.bo.buftype) then
							vim.w.focus_disable = true
						else
							vim.w.focus_disable = false
						end
					end,
				},
				{
					event = { "FileType" },
					command = function(_)
						if vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
							vim.b.focus_disable = true
						else
							vim.b.focus_disable = false
						end
					end,
				},
			})

			focus.setup({
				enable = true,
				commands = true,
				autoresize = {
					enable = true,
				},
				ui = {
					cursorline = false,
					signcolumn = false,
				},
			})
		end,
	},
}
