-- Code actions
return {
	{
		"max397574/better-escape.nvim",
		event = "VeryLazy",
		config = function()
			require("better_escape").setup()

			local group = vim.api.nvim_create_augroup("CustomBetterEscapeOverrides", { clear = true })
			local target_filetypes = { "snacks_terminal", "lazygit" }

			vim.api.nvim_create_autocmd("BufEnter", {
				pattern = target_filetype,
				group = group,
				desc = "Disable better-escape jk/kj for specific filetypes",
				callback = function(args)
					if vim.tbl_contains(target_filetypes, vim.bo.filetype) then
						-- Removing the terminal keys for better escape to work with lazygit in snacks_terminal
						vim.keymap.del("t", "j")
						vim.keymap.del("t", "k")
					end
				end,
			})
		end,
	},
	{ "echasnovski/mini.comment", event = "VeryLazy", config = true },
	{ "echasnovski/mini.move", event = "VeryLazy", config = true },
	{ "echasnovski/mini.surround", event = "VeryLazy", config = true },
	{
		"echasnovski/mini.pairs",
		event = "VeryLazy",
		opts = {
			modes = { insert = true, command = true, terminal = true },
		},
	},
	{
		"echasnovski/mini.bufremove",
		keys = {
			{
				"<leader>q",
				function()
					require("mini.bufremove").delete()
				end,
			},
		},
		config = true,
	},
	{
		"echasnovski/mini.ai",
		event = "VeryLazy",
		opts = function()
			local ai = require("mini.ai")
			return {
				n_lines = 500,
				custom_textobjects = {
					o = ai.gen_spec.treesitter({ -- code block
						a = { "@block.outer", "@conditional.outer", "@loop.outer" },
						i = { "@block.inner", "@conditional.inner", "@loop.inner" },
					}),
					f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }), -- function
					c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }), -- class
					t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" }, -- tags
					d = { "%f[%d]%d+" }, -- digits
					e = { -- Word with case
						{
							"%u[%l%d]+%f[^%l%d]",
							"%f[%S][%l%d]+%f[^%l%d]",
							"%f[%P][%l%d]+%f[^%l%d]",
							"^[%l%d]+%f[^%l%d]",
						},
						"^().*()$",
					},
					u = ai.gen_spec.function_call(), -- u for "Usage"
					U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }), -- without dot in function name
				},
			}
		end,
	},
}
