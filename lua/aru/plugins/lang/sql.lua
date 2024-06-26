local utils = require("aru.utils")

local sql_ft = { "sql", "mysql", "plsql", "dbt" }

return {

	{
		"nvim-treesitter/nvim-treesitter",
		optional = true,
		opts = { ensure_installed = { "sql" } },
	},

	{
		"williamboman/mason.nvim",
		optional = true,
		opts = { ensure_installed = { "sqlfluff", "sqls", "jinja-lsp" } },
	},

	{ "tpope/vim-dadbod", cmd = "DB" },
	{
		"kristijanhusak/vim-dadbod-completion",
		dependencies = "vim-dadbod",
		ft = sql_ft,
		init = function()
			utils.create_augroup("AruSqlDadbodCompletion", {
				{
					event = { "FileType" },
					pattern = sql_ft,
					command = function()
						local cmp = require("cmp")

						-- We grab whatever sources we have defined in cmp
						-- and add the dadbod-completion to it.
						local sources = vim.tbl_map(function(source)
							return { name = source.name }
						end, cmp.get_config().sources)
						table.insert(sources, { name = "vim-dadbod-completion" })

						-- We then add it to the buffer.
						cmp.setup.buffer({ sources = sources })
					end,
				},
			})
		end,
	},
	{

		"kristijanhusak/vim-dadbod-ui",
		cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
		dependencies = "vim-dadbod",
		keys = {
			{ "<leader>D", "<cmd>DBUIToggle<CR>", desc = "Toggle DBUI" },
		},
		init = function()
			local data_path = vim.fn.stdpath("data")

			vim.g.db_ui_auto_execute_table_helpers = 1
			vim.g.db_ui_save_location = data_path .. "/dadbod_ui"
			vim.g.db_ui_show_database_icon = true
			vim.g.db_ui_tmp_query_location = data_path .. "/dadbod_ui/tmp"
			vim.g.db_ui_use_nerd_fonts = true
			vim.g.db_ui_use_nvim_notify = false
			vim.g.db_ui_force_echo_notifications = false
			vim.g.db_ui_disable_mappings = false

			vim.g.db_ui_table_helpers = {
				postgresql = {
					List = "select * from {optional_schema}{table} limit 10;",
					Count = "select count(*) from {optional_schema}{table};",
				},
			}

			-- NOTE: The default behavior of auto-execution of queries on save is disabled
			-- this is useful when you have a big query that you don't want to run every time
			-- you save the file running those queries can crash neovim to run use the
			-- default keymap: <leader>S
			vim.g.db_ui_execute_on_save = false

			utils.create_augroup("DbodUI", {
				{
					-- Handles smart resizing of the dbui window
					event = { "TextChanged" },
					pattern = "dbui",
					command = function(state)
						local help = require("aru.utils.helpers")

						local threshold = 2
						local bufnr = state.buf

						local winid = vim.fn.bufwinid(bufnr)
						local bufcol = help.find_max_column(bufnr)
						local wincol = vim.api.nvim_win_get_width(winid)

						if bufcol > (wincol + threshold) then
							vim.api.nvim_win_set_width(winid, bufcol + threshold)
						end

						if wincol > (bufcol + threshold) then
							vim.api.nvim_win_set_width(winid, bufcol + threshold)
						end
					end,
				},
				{
					event = { "FileType" },
					pattern = sql_ft,
					command = function()
						vim.keymap.set(
							"n",
							"<leader>dw",
							"<Plug>(DBUI_SaveQuery)",
							{ noremap = false, silent = true, buffer = 0 }
						)
						vim.keymap.set(
							"n",
							"<leader>de",
							"<Plug>(DBUI_EditBindParameters)",
							{ noremap = false, silent = true, buffer = 0 }
						)
						vim.keymap.set(
							{ "n", "v" },
							"<leader>ds",
							"<Plug>(DBUI_ExecuteQuery)",
							{ noremap = false, silent = true, buffer = 0 }
						)
					end,
				},
			})
		end,
	},

	{
		"nanotee/sqls.nvim",
		ft = sql_ft,
		dependencies = {
			{ "nvim-lspconfig", optional = true },
		},
		config = function()
			local lspconfig = require("lspconfig")
			local capabilities = require("cmp_nvim_lsp").default_capabilities()

			lspconfig.jinja_lsp.setup({
				filetypes = { "jinja", "sql" },
				capabilities = capabilities,
			})

			lspconfig.sqls.setup({
				capabilities = capabilities,
				on_attach = function(client, bufnr)
					require("sqls").on_attach(client, bufnr)
				end,
			})
		end,
	},
	{
		"PedramNavid/dbtpal",
		ft = sql_ft,
		dependencies = {
			"plenary.nvim",
			"telescope.nvim",
		},
		config = function()
			local dbt = require("dbtpal")

			dbt.setup()

			vim.keymap.set("n", "<leader>drf", dbt.run)
			vim.keymap.set("n", "<leader>drp", dbt.run_all)
			vim.keymap.set("n", "<leader>dtf", dbt.test)
			vim.keymap.set("n", "<leader>dm", require("dbtpal.telescope").dbt_picker)

			-- Enable Telescope Extension
			require("telescope").load_extension("dbtpal")
		end,
	},

	-- Linters & formatters
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			for _, ft in ipairs(sql_ft) do
				opts.linters_by_ft[ft] = opts.linters_by_ft[ft] or {}
				table.insert(opts.linters_by_ft[ft], "sqlfluff")
			end
		end,
	},
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			for _, ft in ipairs(sql_ft) do
				opts.formatters_by_ft[ft] = opts.formatters_by_ft[ft] or {}
				table.insert(opts.formatters_by_ft[ft], "sqlfluff")
			end
		end,
	},
}
