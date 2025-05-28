return {
	{
		"neovim/nvim-lspconfig",
		lazy = true,
		config = function()
			-- This is where you enable features that only work
			-- if there is a language server active in the file
			vim.api.nvim_create_autocmd("LspAttach", {
				desc = "LSP actions",
				callback = function(event)
					local opts = { buffer = event.buf }

					vim.keymap.set("n", "K", "<cmd>lua vim.lsp.buf.hover()<cr>", opts)
					vim.keymap.set("n", "<c-k>", "<cmd>lua vim.lsp.buf.signature_help()<cr>", opts)

					-- vim.keymap.set("n", "gd", "<cmd>lua vim.lsp.buf.definition()<cr>", opts)
					-- vim.keymap.set("n", "gD", "<cmd>lua vim.lsp.buf.declaration()<cr>", opts)
					-- vim.keymap.set("n", "gi", "<cmd>lua vim.lsp.buf.implementation()<cr>", opts)
					-- vim.keymap.set("n", "go", "<cmd>lua vim.lsp.buf.type_definition()<cr>", opts)
					-- vim.keymap.set("n", "gr", "<cmd>lua vim.lsp.buf.references()<cr>", opts)

					vim.keymap.set({ "n", "x" }, "crf", "<cmd>lua vim.lsp.buf.format({async = true})<cr>", opts)
					vim.keymap.set("n", "crr", "<cmd>lua vim.lsp.buf.code_action()<cr>", opts)
					vim.keymap.set("n", "crn", "<cmd>lua vim.lsp.buf.rename()<cr>", opts)
				end,
			})
		end
	},
	{
		"saghen/blink.cmp",
		version = "1.*",
		event = "InsertEnter",
		opts = { ---@type blink.cmp.Config
			signature = { enabled = true },
			cmdline = { keymap = { preset = "inherit" }, completion = { menu = { auto_show = true }} },
			fuzzy = { implementation = "prefer_rust_with_warning" },

			sources = {
				default = { "lazydev", "lsp", "path", "buffer" },
				providers = {
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 100,
					},
				},
			},

			completion = {
				documentation = {
					auto_show = true,
					auto_show_delay_ms = 150,
					window = {
						border = "padded",
					},
				},
				ghost_text = {
					enabled = false,
					show_with_menu = false,
				},
				trigger = {
					show_on_keyword = true,
					show_on_trigger_character = true,
					show_on_insert_on_trigger_character = true,
					show_on_x_blocked_trigger_characters = {
						"'",
						'"',
					},
					show_on_blocked_trigger_characters = {
						"\n",
						"\t",
					},
				},
				menu = {
					draw = {
						columns = {
							{ "kind_icon", gap = 1 },
							{ "label", "label_description", gap = 1 },
						},
						components = {
							kind_icon = {
								highlight = function(ctx)
									return ctx.kind_hl
								end,
							},
						},
					},
				},
			},
			-- keymap = {
			-- 	preset = "none",
			-- 	["<S-Up>"] = { "show", "select_prev", "fallback" },
			-- 	["<S-Down>"] = { "show", "select_next", "fallback" },
			-- 	["<F1>"] = { "show", "select_and_accept", "fallback" },
			-- 	["<Tab>"] = { "select_and_accept", "fallback" },
			-- 	["<F2>"] = { "show", "hide", "fallback" },
			-- },
		},
		config = function(config)
			local opts = config.opts
			while type(opts) == "function" do
				opts = opts(config, {})
			end

			require("blink.cmp").setup(opts)
			local palette = require("rose-pine.palette")
			require("rabbit.term.highlight").apply({
				BlinkCmpLabelDeprecated = {
					force = true,
					fg = palette.love,
					strikethrough = true,
				},
				BlinkCmpKindMethod = {
					force = true,
					fg = palette.love,
					bold = true,
				},
				BlinkCmpKindFunction = {
					force = true,
					link = "BlinkCmpKindMethod",
				},
				BlinkCmpConstructor = {
					force = true,
					fg = palette.iris,
					bold = true,
				},
			})


			-- This is copied straight from blink
			-- https://cmp.saghen.dev/installation#merging-lsp-capabilities
			-- local capabilities = {
			-- 	textDocument = {
			-- 		foldingRange = {
			-- 			dynamicRegistration = false,
			-- 			lineFoldingOnly = true,
			-- 		},
			-- 	},
			-- }
			-- capabilities = require("blink.cmp").get_lsp_capabilities(capabilities)
			-- vim.lsp.config("*", {
			-- 	capabilities = capabilities,
			-- 	root_markers = { ".git" },
			-- })

		end,
	},
	{
		"folke/lazydev.nvim",
		ft = "lua",
		config = true,
		opts = { ---@type lazydev.Config
			runtime = vim.env.VIMRUNTIME --[[@as string]],
			integrations = {
				lspconfig = true,
				cmp = true,
				coq = false,
			},
			-- library = {
			-- 	{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			-- 	{ path = lazypath .. "lazy.nvim", words = { "LazyPlugin", "LazyPluginSpec" } },
			-- 	{ path = lazypath .. "lazydev.nvim", words = { "lazydev" } },
			-- },
			enabled = true,
			debug = false,
		},
	},
	{
		"mfussenegger/nvim-dap",
		event = "LspAttach",
		config = function()
			local dap = require("dap")
			require("which-key").add({
				{ "<leader>d", name = "Debug" },
			})

			---@param func fun(opts: any)
			---@return fun()
			local function bind(func)
				return function()
					func()
				end
			end

			vim.keymap.set("n", "<leader>dB", bind(dap.clear_breakpoints), { desc = "Clear bps" })
			vim.keymap.set("n", "<leader>db", bind(dap.toggle_breakpoint), { desc = "Breakpoint" })
			vim.keymap.set("n", "<leader>dc", bind(dap.continue), { desc = "Continue" })
			vim.keymap.set("n", "<leader>dt", bind(dap.terminate), { desc = "Terminate" })
			vim.keymap.set("n", "<leader>ds", bind(dap.step_over), { desc = "Step next" })
			vim.keymap.set("n", "<leader>dS", bind(dap.step_into), { desc = "Step back" })
		end,
	},
}
