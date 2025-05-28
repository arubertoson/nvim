local helper = require("aru.helper")
local log = require("aru.logging").get_logger("AruLSP", "INFO") -- Explicitly setting logger name and level


local function configure_keymaps(client, bufnr)
	local bufmap = function(mode, rhs, lhs)
		vim.keymap.set(mode, rhs, lhs, { buffer = bufnr })
	end

	bufmap("n", "gd", Snacks.picker.lsp_definitions)
	bufmap("n", "gD", Snacks.picker.lsp_declarations)
	bufmap("n", "gr", Snacks.picker.lsp_references)
	bufmap("n", "gI", Snacks.picker.lsp_implementations)
	bufmap("n", "gy", Snacks.picker.lsp_type_definitions)

	bufmap("n", "fs", Snacks.picker.lsp_symbols)
	bufmap("n", "fS", Snacks.picker.lsp_workspace_symbols)
	bufmap("n", "fd", Snacks.picker.diagnostics_buffer)
	bufmap("n", "fD", Snacks.picker.diagnostics)

	bufmap("n", "gO", "<cmd>lua vim.lsp.buf.document_symbol()<cr>")
	bufmap({ "i", "s" }, "<C-s>", "<cmd>lua vim.lsp.buf.signature_help()<cr>")
	bufmap({ "n", "x" }, "gq", "<cmd>lua vim.lsp.buf.format({async = true})<cr>")

	bufmap("n", "K", "<cmd>lua vim.lsp.buf.hover()<cr>")
	bufmap("n", "grn", "<cmd>lua vim.lsp.buf.rename()<cr>")
	bufmap("n", "gra", "<cmd>lua vim.lsp.buf.code_action()<cr>")
end

local function configure_diagnostics()
	vim.diagnostic.config({
		virtual_text = false,
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = "",
				[vim.diagnostic.severity.WARN] = "",
				[vim.diagnostic.severity.INFO] = "",
				[vim.diagnostic.severity.HINT] = "",
			},
			numhl = {
				[vim.diagnostic.severity.WARN] = "WarningMsg",
				[vim.diagnostic.severity.ERROR] = "ErrorMsg",
				[vim.diagnostic.severity.INFO] = "DiagnosticInfo",
				[vim.diagnostic.severity.HINT] = "DiagnosticHint",
			},
		},
	})
end

return {
	{
		"neovim/nvim-lspconfig",
		lazy = false,
		config = function()
			-- Load language specific lsp configurations.
			local path = vim.fn.stdpath("config") .. "/lua/aru-lsp/lang"

			for _, file in ipairs(vim.fn.readdir(path)) do
				if file:match("%.lua$") then
					local module_name = "aru-lsp.lang." .. file:gsub("%.lua$", "")
					require(module_name)
				end
			end

			helper.create_augroup("AruLSP", {
				{
					event = { "LspAttach" },
					description = "Setup LSP Client for buffer",
					command = function(event)
						local client = assert(vim.lsp.get_client_by_id(event.data.client_id))
						local bufnr = event.buf

						if
							client
							and client.supports_method("textDocument/inlayHint", bufnr)
						then
							vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
						end

						configure_keymaps(client, bufnr)
						configure_diagnostics()
					end,
				},
			})
		end,
	},
}
