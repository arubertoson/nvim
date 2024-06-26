--[[ lsp keymap setup

This module helps with the setup of general lsp keymaps, it includes capability checks to ensure
that we are opereating with valid lsp features.

Usage:
	local keymaps = require("aru.utils.lsp.keymaps")
	vim.list_extend(keymaps.get(), ...)

	lsp.on_attach(keymaps.on_attach)
]]
local fmt = string.format
local aru = require("aru")

local M = {}

---@class Keymap
---@field [1] string[] Modes
---@field [2] string Keybinding
---@field [3] function LSP function to call
---@field [4] table Options for the keybinding
---@field [5] table Conditions for the keybinding (optional)

---@type Keymap[]
M._keys = nil

function M.get()
	if M._keys then
		return M._keys
	end

	-- stylua: ignore
	M._keys =  {
		-- Goto related mappings
		{ { "n" }, "K", vim.lsp.buf.hover, { desc = "Hover", } },
		{ { "n" }, "gr", vim.lsp.buf.references, { desc = "References", nowait = true } },
		{ { "n" }, "gI", vim.lsp.buf.implementation, { desc = "Goto Implementation" } },
		{ { "n" }, "gD", vim.lsp.buf.declaration, { desc = "Goto Declaration" } },
		{ { "n" }, "gy", vim.lsp.buf.type_definition, { desc = "Goto T[y]pe Definition" } },
		{ { "n" }, "gK", vim.lsp.buf.signature_help, { desc = "Signature Help" }, { capability = "textDocument/signatureHelp" } },
		{ { "i" }, "<c-k>", vim.lsp.buf.signature_help, { desc = "Signature Help" }, { capability = "textDocument/signatureHelp" } },
		{ { "n" }, "gd", vim.lsp.buf.definition, { desc = "Goto Definition" }, { capability = "textDocument/definition" } },

		-- Toggle related functionality
		{ { "n" }, "<leader>li", function() require("aru.utils.lsp").toggle.inlay_hint(0) end, { desc = "Inlay hint toggle" }, { capability = "textDocument/inlayHint" } },
		{ { "n" }, "<leader>lc", function() require("aru.utils.lsp").toggle.codelens(0) end, { desc = "Display codelens" }, { capability = "textDocument/codeLens" } },

		-- Refactoring mappings
		{ { "n", "v" }, "crr", vim.lsp.buf.code_action, { desc = "Code Action" }, { capability = "textDocument/codeAction" } },
		{ { "n" }, "crn", vim.lsp.buf.rename, { desc = "Rename" }, { capability = "textDocument/rename" } },
	}

	return M._keys
end

function M.add(keymaps)
	local current = M.get()

	-- Create a lookup table for existing keys
	local current_keys = {}
	for idx, cur_spec in ipairs(current) do
		local current_key = cur_spec[2]
		current_keys[current_key] = idx
	end

	for _, spec in ipairs(keymaps) do
		local other_key = spec[2]
		local idx = current_keys[other_key]

		if idx then
			aru.log:debug(fmt("Replacing key: [%d::%s] with other.", idx, other_key))

			current[idx] = spec
		else
			table.insert(current, spec)
		end
	end
end

function M.set(wanted, opts)
	local filtered_keys = {}

	for _, spec in ipairs(M.get()) do
		local key_cond = spec[5]

		if key_cond and key_cond.capability and vim.tbl_contains(wanted, key_cond.capability) then
			spec[4] = vim.tbl_extend("force", spec[4], opts or {})

			table.insert(filtered_keys, spec)
		end
	end

	require("aru.utils.keymaps").set_maps(filtered_keys)
end

local function _check_capability(buffer, method)
	local clients = vim.lsp.get_clients({ bufnr = buffer })
	for _, client in ipairs(clients) do
		if client.supports_method(method) then
			return true
		end
	end

	return false
end

function M.on_attach(_, buffer)
	local valid_keys = {}

	for _, spec in ipairs(M.get()) do
		local key_cond = spec[5]
		if key_cond and key_cond.capability then
			if _check_capability(buffer, key_cond.capability) then
				table.insert(valid_keys, spec)
			end
		else
			table.insert(valid_keys, spec)
		end

		-- Ensure that we set this up on the current buffer
		spec[4].buffer = buffer
	end

	require("aru.utils.keymaps").set_maps(valid_keys)
end

return M
