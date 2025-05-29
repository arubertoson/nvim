return {
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufWritePre", "BufReadPost", "InsertLeave" },
		config = function()
			require("gitsigns").setup({
				on_attach = function(bufnr)
					local gs = require("gitsigns")

					local nav_opts = {
						wrap = true,
						preview = true,
					}
					local key_opts = {
						buffer = bufnr,
					}

					vim.keymap.set("n", "]c", function()
						gs.nav_hunk("next", nav_opts)
					end, key_opts)
					vim.keymap.set("n", "[c", function()
						gs.nav_hunk("prev", nav_opts)
					end, key_opts)

					vim.keymap.set("n", "<leader>hp", gs.preview_hunk_inline, key_opts)
					vim.keymap.set("n", "<leader>hs", gs.stage_hunk, key_opts)
					vim.keymap.set("n", "<leader>hr", gs.reset_hunk, key_opts)
				end,
			})
		end,
	},
}
