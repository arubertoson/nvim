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
			require("focus").setup({
				enable = true,
				commands = true,
				autoresize = {
					enable = false,
				},
				ui = {
					cursorline = false,
					signcolumn = false,
				},
			})
		end,
	},
}
