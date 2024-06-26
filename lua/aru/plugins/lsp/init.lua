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
			}
		end,
		config = function(_, opts)
			local ulsp = require("aru.utils.lsp")
			local keys = require("aru.plugins.lsp.keymaps")
			local lspconfig = require("lspconfig")

			-- Setup special handling of capabilities registration.
			ulsp.setup()

			-- Add global callback to keybindings
			ulsp.on_attach(keys.on_attach)

			-- Special handling for some dynamic functionality, this is most likely not
			-- necessary with the setup we are currently using (getting all possible
			-- capabilities up front and sending them to the config). But it's here
			-- nevertheless.
			ulsp.on_supports_method("textDocument/inlayHint", function(_, buffer)
				keys.set({ "textDocument/inlayHint" }, { buffer = buffer })
			end)
			ulsp.on_supports_method("textDocument/codeLens", function(_, buffer)
				keys.set({ "textDocument/codeLens" }, { buffer = buffer })
			end)

			-- We grab everything we can in terms of capabilities and will have the
			-- tbl_deep_extend sort out the collisions, the priorities are set from top
			-- to bottom where opts will have the final say.
			local capabilities = {}
			local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
			if has_cmp then
				capabilities = cmp_nvim_lsp.default_capabilities() or {}
			end
			capabilities = vim.tbl_deep_extend(
				"force",
				vim.lsp.protocol.make_client_capabilities() or {},
				capabilities,
				opts.capabilities or {}
			)

			for name, config in pairs(opts.servers) do
				if config == true then
					config = {}
				end

				-- Same story as above, anything that has been explicitly configured
				-- will have precedence.
				config = vim.tbl_deep_extend("force", { capabilities = capabilities }, config)

				lspconfig[name].setup(config)
			end
		end,
	},
}
