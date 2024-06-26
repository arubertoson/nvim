return {
	{
		"neovim/nvim-lspconfig",
		event = "InsertEnter",
		dependencies = {
			{ "j-hui/fidget.nvim", opts = {} },
		},
		opts = function()
			return {
				format = {
					formatting_options = nil,
					timeout_ms = nil,
				},
				servers = {
					lua_ls = {
						settings = {
							Lua = {
								workspace = {
									checkThirdParty = false,
								},
								-- codeLens = {
								-- 	enable = true,
								-- },
								completion = {
									callSnippet = "Replace",
								},
								doc = {
									privateName = { "^_" },
								},
								hint = {
									enable = true,
									paramType = true,
									-- setType = false,
									-- paramName = "Disable",
									-- semicolon = "Disable",
									-- arrayIndex = "Disable",
								},
							},
						},
					},
				},
			}
		end,
		config = function(_, opts)
			local utils = require("aru.utils")
			local lspconfig = require("lspconfig")

			-- Setup Capabilities
			local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
			local capabilities = {}
			if has_cmp then
				capabilities = cmp_nvim_lsp.default_capabilities() or {}
			end
			capabilities = vim.tbl_deep_extend(
				"force",
				vim.lsp.protocol.make_client_capabilities() or {},
				opts.capabilities or {}
			)

			-- Set up each server through lspconfig
			for name, config in pairs(opts.servers) do
				if config == true then
					config = {}
				end

				config = vim.tbl_deep_extend("force", {}, {
					capabilities = capabilities,
				}, config)

				lspconfig[name].setup(config)
			end

			-- Setup LspAttach stuff
			utils.create_augroup("AruLspAttach", {
				{
					event = "LspAttach",
					command = function(args)
						vim.opt_local.omnifunc = "v:lua.vim.lsp.omnifunc"

						local bufnr = args.bufnr
						local client = vim.lsp.get_client_by_id(args.data.client_id)

						if client == nil then
							return
						end

						vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = 0 })
						vim.keymap.set("n", "gr", vim.lsp.buf.references, { buffer = 0 })
						vim.keymap.set("n", "gI", vim.lsp.buf.implementation, { buffer = 0 })
						vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buffer = 0 })
						vim.keymap.set("n", "gT", vim.lsp.buf.type_definition, { buffer = 0 })
						vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = 0 })
						vim.keymap.set("n", "gK", vim.lsp.buf.signature_help, { buffer = 0 })

						vim.keymap.set("n", "<space>cr", vim.lsp.buf.rename, { buffer = 0 })
						vim.keymap.set(
							"n",
							"<space>ca",
							vim.lsp.buf.code_action,
							{ buffer = 0 }
						)
						vim.keymap.set({ "n" }, "<space>ci", "<cmd>LspInfo<cr>", { buffer = 0 })

						if client.server_capabilities.codeLensProvider then
							vim.keymap.set(
								{ "n", "v" },
								"<leader>cll",
								vim.lsp.codelens.run,
								{ buffer = 0 }
							)
							vim.keymap.set(
								"n",
								"<leader>clr",
								vim.lsp.codelens.refresh,
								{ buffer = 0 }
							)

							require("aru.utils").create_augroup("AruCodeLens", {
								{
									event = {
										"CursorHold",
										"CursorHoldI",
										"InsertLeave",
									},
									buffer = bufnr,
									command = function() end,
								},
							})
							vim.lsp.codelens.refresh()
						end
					end,
				},
			})
		end,
	},
}
