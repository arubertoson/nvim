return {
	{
		"nanozuki/tabby.nvim",
		event = "VeryLazy",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
		config = function()
			vim.o.showtabline = 2

			local theme = {
				head = "TabLine",
				-- Also you can do this: fill = { fg='#f2e9de', bg='#907aa9', style='italic' }
				tab = "TabLine",
				win = "Normal",
				tail = "TabLine",
				current_tab = "TabLineSel",
				fill = "TabLineFill",
			}
			require("tabby.tabline").set(function(line)
				return {
					{
						{ "  ", hl = theme.head },
						line.sep("", theme.head, theme.fill),
					},
					line.tabs().foreach(function(tab)
						local hl = tab.is_current() and theme.current_tab or theme.tab
						return {
							line.sep("", hl, theme.fill),
							tab.is_current() and "" or "",
							-- TODO: When renaming the tab we should
							-- take that instead of the number.
							tab.number(),
							line.sep("", hl, theme.fill),
							hl = hl,
							margin = " ",
						}
					end),
					line.spacer(),
					line.wins_in_tab(line.api.get_current_tab()).foreach(function(win)
						return {
							line.sep("", theme.win, theme.fill),
							win.is_current() and "" or "",
							win.buf_name(),
							line.sep("", theme.win, theme.fill),
							hl = theme.win,
							margin = " ",
						}
					end),
					{
						line.sep("", theme.tail, theme.fill),
						{ "  ", hl = theme.tail },
					},
					hl = theme.fill,
				}
			end)
		end,
	},
}
