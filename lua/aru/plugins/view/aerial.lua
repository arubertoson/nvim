return {
	{
		"stevearc/aerial.nvim",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"nvim-tree/nvim-web-devicons",
		},
		cmd = { "AerialToggle" },
		-- keys = {
		-- 	{ "<leader>a", "<cmd>AerialToggle!<CR>", desc = "Aerial" },
		-- }
		config = function()
			require("aerial").setup({
			  -- optionally use on_attach to set keymaps when aerial has attached to a buffer
			  on_attach = function(bufnr)
			    -- Jump forwards/backwards with '{' and '}'
			    vim.keymap.set("n", "{", "<cmd>AerialPrev<CR>", { buffer = bufnr })
			    vim.keymap.set("n", "}", "<cmd>AerialNext<CR>", { buffer = bufnr })
			  end,
			})
			-- You probably also want to set a keymap to toggle aerial
			vim.keymap.set("n", "<leader>a", "<cmd>AerialToggle!<CR>")
		end,
	},

	{
		"folke/edgy.nvim",
		optional = true,
		opts = function(_, opts)
			opts.right = opts.right or {}
			table.insert(opts.right, {
				title = "Aerial",
				ft = "aerial",
				pinned = true,
				width = 0.3,
				open = function()
					vim.cmd("AerialToggle")
				end,
			})
		end,
	},
}
