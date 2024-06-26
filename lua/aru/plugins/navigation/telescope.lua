return {
	{
		"nvim-telescope/telescope.nvim",
		version = false,
		cmd = "Telescope",
		dependencies = {
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
				config = function(_)
					local aru = require("aru")

					local ok, err = pcall(require("telescope").load_extension, "fzf")
					if not ok then
						aru.log:error("failed to load `telescope-fzf-native.nvim" .. err)
					end
				end,
			},

			{
				"nvim-telescope/telescope-ui-select.nvim",
				config = function(_)
					local aru = require("aru")

					local ok, err = pcall(require("telescope").load_extension, "ui-select")
					if not ok then
						aru.log:error("failed to load `telescope-ui-select.nvim" .. err)
					end
				end,
			},
		},
		keys = {

			{ "<leader>?", "<cmd>Telescope help_tags<CR>", desc = "Help tags" },
			{ "<C-p>", "<cmd>Telescope git_files<CR>", desc = "Find git repository files" },
			{
				"<leader>pf",
				"<cmd>Telescope find_files hidden=true<CR>",
				desc = "Find Files including hidden",
			},
			{
				"<leader>ps",
				function()
					require("telescope.builtin").grep_string({ search = vim.fn.input("Grep > ") })
				end,
				desc = "Search the results of a grep.",
			},
			{
				"<leader>/",
				"<cmd>Telescope current_buffer_fuzzy_find<CR>",
				desc = "Fuzzy find in current buffer",
			},
			{
				"n",
				"<leader>pws",
				function()
					local word = vim.fn.expand("<cword>")
					require("telescope.builtin").grep_string({ search = word })
				end,
				desc = "find word",
			},
			{
				"n",
				"<leader>pWs",
				function()
					local word = vim.fn.expand("<cWORD>")
					require("telescope.builtin").grep_string({ search = word })
				end,
				{ desc = "find word-expanded" },
			},

			-- Quick Navigation to config files
			{
				"n",
				"<leader>pa",
				function()
					require("telescope.builtin").find_files({
						---@diagnostic disable-next-line: param-type-mismatch
						cwd = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy"),
					})
				end,
				desc = "find plugin source files",
			},
			{
				"n",
				"<leader>pn",
				function()
					require("telescope.builtin").find_files({ cwd = vim.fn.stdpath("config") })
				end,
				desc = "find config files",
			},
		},
		config = function()
			require("telescope").setup({
				extensions = {
					wrap_results = true,
					fzf = {},
					["ui-select"] = {
						require("telescope.themes").get_dropdown(),
					},
				},
			})
		end,
	},

	-- better vim.ui with telescope
	{
		"stevearc/dressing.nvim",
		lazy = true,
		init = function()
			---@diagnostic disable-next-line: duplicate-set-field
			vim.ui.select = function(...)
				require("lazy").load({ plugins = { "dressing.nvim" } })
				return vim.ui.select(...)
			end
			---@diagnostic disable-next-line: duplicate-set-field
			vim.ui.input = function(...)
				require("lazy").load({ plugins = { "dressing.nvim" } })
				return vim.ui.input(...)
			end
		end,
	},

	{
		"neovim/nvim-lspconfig",
		optional = true,
		opts = function()
			local builtin = require("telescope.builtin")
			local keys = require("aru.plugins.lsp.keymaps")

			-- stylua: ignore start
			keys.add({
				{ { "n" }, "gr", "<cmd>Telescope lsp_references<cr>", { desc = "References", nowait = true  }},
				{ { "n" }, "gd", function() builtin.lsp_definitions({ reuse_win = true }) end, { desc = "Goto Definition" }, { copability = "textDocument/definition" } },
				{ { "n" }, "gI", function() builtin.lsp_implementations({ reuse_win = true }) end, { desc = "Goto Implementation" }, },
				{ { "n" }, "gy", function() builtin.lsp_type_definitions({ reuse_win = true }) end, { desc = "Goto T[y]pe Definition" } },
				{ { "n" }, "<leader>lw", builtin.lsp_dynamic_workspace_symbols, { desc = "Workspace Symbols" } },
			})
		end,
	},
}
