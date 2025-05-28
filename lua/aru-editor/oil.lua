function ToggleOil()
	if vim.bo[0].filetype == "oil" then
		require("oil").discard_all_changes()
		require("oil").close()
	else
		require("oil").open_float()
	end
end

function ToggleCwdOil()
	if vim.bo[0].filetype == "oil" then
		require("oil").discard_all_changes()
		require("oil").close()
	else
		require("oil").open_float(vim.fn.getcwd())
	end
end

return {
	{
		"stevearc/oil.nvim",
		dependencies = { { "echasnovski/mini.icons", version = "*" } },
		lazy = false,
		cmd = "Oil",
		config = function()
			require("oil").setup({
				view_options = {
					show_hidden = true,
				},
				float = { padding = 8 },
				watch_for_changes = true,
				skip_confirm_for_simple_edits = true,
				keymaps = {
					q = "actions.close",
					["<C-k>"] = "actions.parent",
					["<C-j>"] = "actions.select",
					["<C-p>"] = "actions.preview",
				},
			})

			-- Open parent directory in current window
			vim.keymap.set("n", "<leader>n", ToggleOil, { desc = "Open Oil" })
			vim.keymap.set("n", "<leader>N", ToggleCwdOil, { desc = "Open Oil" })
		end,
	},
}
