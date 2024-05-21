return {
	{
		"nvim-telescope/telescope.nvim",
		version = false,
		dependencies = {
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
				config = function(plugin)
					local aru = require("aru")

					local ok, err = pcall(require("telescope").load_extension, "fzf")
					if not ok then
						aru.log:error("failed to load `telescope-fzf-native.nvim" .. err)
					end
				end,
			},

			{
				"nvim-telescope/telescope-ui-select.nvim",
				config = function(plugin)
					local aru = require("aru")

					local ok, err = pcall(require("telescope").load_extension, "ui-select")
					if not ok then
						aru.log:error("failed to load `telescope-ui-select.nvim" .. err)
					end
				end,
			},
		},
		config = function()
			local data = assert(vim.fn.stdpath("data")) --[[@as string]]

			require("telescope").setup({
				extensions = {
					wrap_results = true,
					fzf = {},
					["ui-select"] = {
						require("telescope.themes").get_dropdown(),
					},
				},
			})

			local builtin = require("telescope.builtin")
			require("aru.utils.keymaps").set_maps({
				-- stylua: ignore start
				{ "n", "<C-p>", builtin.git_files, { desc = "find git files" } },
				{ "n", "<leader>pf", { builtin.find_files, { hidden = true } }, { desc = "find files" } },
				{ "n", "<leader>ps", function() builtin.grep_string({ search = vim.fn.input("Grep > ")}) end, { desc = "Grep string" } },
				{ "n", "<leader>/", builtin.current_buffer_fuzzy_find, { desc = "current buffer fuzzy find" } },

				{
					"n",
					"<leader>pws",
					function()
						local word = vim.fn.expand("<cword>")
						builtin.grep_string({ search = word })
					end,
					{ desc = "find word" },
				},
				{
					"n",
					"<leader>pWs",
					function()
						local word = vim.fn.expand("<cWORD>")
						builtin.grep_string({ search = word })
					end,
					{ desc = "find word-expanded" },
				},

				-- Quick Navigation to config files
				{
					"n",
					"<leader>pa",
					function()
						---@diagnostic disable-next-line: param-type-mismatch
						builtin.find_files({
							cwd = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy"),
						})
					end,
					{ desc = "find plugin source files" },
				},
				{
					"n",
					"<leader>pn",
					function()
						builtin.find_files({ cwd = vim.fn.stdpath("config") })
					end,
					{ desc = "find config files" },
				},
				{ "n", "<leader>ph", builtin.help_tags, { desc = "Help tags" } },
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
			print("exciting, I need to write th lsp utils")
			-- local builtin = require("telescope.builtin")
			-- local Keys = require("lazyvim.plugins.lsp.keymaps").get()
			--
			-- -- stylua: ignore start
			-- vim.list_extend(Keys, {
			-- 	{ "gr", "<cmd>Telescope lsp_references<cr>", desc = "References", nowait = true },
			-- 	{ "n", "<leader>lw", builtin.lsp_dynamic_workspace_symbols, { desc = "workspace symbols" } },
			-- 	{ "gd", function() builtin.lsp_definitions({ reuse_win = true }) end, desc = "Goto Definition", has = "definition", },
			-- 	{ "gI", function() builtin.lsp_implementations({ reuse_win = true }) end, desc = "Goto Implementation", },
			-- 	{ "gy", function() builtin.lsp_type_definitions({ reuse_win = true }) end, desc = "Goto T[y]pe Definition", },
			-- })
			-- -- stylua: ignore end
		end,
	},
}
