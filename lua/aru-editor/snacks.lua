return {
	{
		"folke/snacks.nvim",
		priority = 1000,
		lazy = false,
		---@type snacks.Config
		opts = {
			-- your configuration comes here
			-- or leave it empty to use the default settings
			-- refer to the configuration section below
			bigfile = { enabled = true },
			input = {
				layout = {
					cycle = true,
					--- Use the default layout or vertical if the window is too narrow
					preset = function()
						return vim.o.columns >= 79 and "default" or "vertical"
					end,
				},
			},
			quickfile = { enabled = true },
			picker = { enabled = true },
			notifier = { enabled = true, width = { min = 40, max = 0.6 }, timeout = 3000 },
			terminal = { enabled = true },
			styles = {},
		},
		keys = {
			-- stylua: ignore start
			{ "<leader>ff", function() Snacks.picker.smart() end, desc = "Smart Find Files" },
			{ "<leader>fs", function() Snacks.picker.grep() end, desc = "Grep" },
			{ "<leader>fw", function() Snacks.picker.grep_word() end, desc = "Visual selection or word", mode = { "n", "x" } },
			{ "<leader>fl", function() Snacks.picker.lines() end, desc = "Buffer Lines" },
			{ "<leader>:", function() Snacks.picker.command_history() end, desc = "Command History" },
			{ "<leader>fc", function() Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end, desc = "Find Config File" },
			{ "<leader>fo", function() Snacks.picker.files({ cwd = vim.fn.stdpath("data") .. "/lazy" }) end, desc = "Find Plugin File" },

			{ "<C-p>", function() Snacks.picker.git_files() end, desc = "Find Git Files" },
			{ "<leader>fh", function() Snacks.picker.help() end, desc = "Help Pages" },
			{ "<leader>fj", function() Snacks.picker.jumps() end, desc = "Jumps" },
			{ "<leader>fk", function() Snacks.picker.keymaps() end, desc = "Keymaps" },
			{ "<leader>fl", function() Snacks.picker.loclist() end, desc = "Location List" },
			{ "<leader>fm", function() Snacks.picker.marks() end, desc = "Marks" },
			{ "<leader>fM", function() Snacks.picker.man() end, desc = "Man Pages" },
			{ "<leader>fp", function() Snacks.picker.lazy() end, desc = "Search for Plugin Spec" },
			{ "<leader>fq", function() Snacks.picker.qflist() end, desc = "Quickfix List" },
			{ "<leader>ih", function() Snacks.notifier.show_history() end, desc = "Notifier History" },

			{ "<leader>gd", function() Snacks.picker.git_diff() end, desc = "Git Diff (Hunks)" },
			{ "<leader>gg", function() Snacks.lazygit() end, desc = "Lazygit" },
			{ "<leader>.", function() Snacks.scratch() end, desc = "Toggle Scratch Buffer" },
			{ "<leader>S", function() Snacks.scratch.select() end, desc = "Select Scratch Buffer" },
			-- stylua: ignore end
		},
	},
}
