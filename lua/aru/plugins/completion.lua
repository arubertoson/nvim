return {
	{
		"hrsh7th/nvim-cmp",
		version = false,
		event = "InsertEnter",
		dependencies = {
			"onsails/lspkind.nvim",
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
			{
				"hrsh7th/cmp-cmdline",
				dependencies = {
					"dmitmel/cmp-cmdline-history",
				},
				config = function()
					local cmp = require("cmp")

					for _, cmd_type in ipairs({ ":", "/", "?", "@" }) do
						cmp.setup.cmdline(cmd_type, {
							sources = {
								{ name = "cmdline" },
								{ name = "cmdline_history" },
								{ name = "buffer" },
								{ name = "path" },
							},
							mapping = {
								["<C-n>"] = cmp.mapping.select_next_item({
									behavior = cmp.SelectBehavior.Insert,
								}),
								["<C-p>"] = cmp.mapping.select_prev_item({
									behavior = cmp.SelectBehavior.Insert,
								}),
								["<C-y>"] = cmp.mapping(
									cmp.mapping.confirm({
										behavior = cmp.ConfirmBehavior.Insert,
										select = true,
									}),
									{ "i", "c" }
								),
							},
						})
					end
				end,
			},
		},
		opts = {
			sources = {
				{ name = "nvim_lsp" },
				{ name = "path" },
				{ name = "buffer" },
			},
		},
		config = function(_, opts)
			-- Module options
			vim.opt.completeopt = { "menu", "menuone", "noselect" }
			vim.opt.shortmess:append("c")

			local cmp = require("cmp")
			local lspkind = require("lspkind")

			lspkind.init({})

			opts = vim.tbl_deep_extend("force", opts, {
				mapping = {
					["<C-n>"] = cmp.mapping.select_next_item({
						behavior = cmp.SelectBehavior.Insert,
					}),
					["<C-p>"] = cmp.mapping.select_prev_item({
						behavior = cmp.SelectBehavior.Insert,
					}),
					["<C-y>"] = cmp.mapping(
						cmp.mapping.confirm({
							behavior = cmp.ConfirmBehavior.Insert,
							select = true,
						}),
						{ "i", "c" }
					),
				},
			})

			cmp.setup(opts)
		end,
	},
}
