local helper = require("aru.helper")
local log = require("aru.logging").get_logger("AruKeymaps", "INFO") -- Explicitly setting logger name and level
local fmt = string.format

local collection = {
	{
		{ "n" },
		"<localleader>q",
		":<C-u>qa<CR>",
		{
			desc = "exit neovim",
			silent = true,
		},
	},
	{
		{ "n" },
		"<localleader>c",
		":<C-u>bd<CR>",
		{
			desc = "delete buffer",
			silent = true,
		},
	},
	{
		{ "n" },
		"<localleader>C",
		":<C-u>wincmd c<CR>",
		{
			desc = "close window",
			silent = true,
		},
	},

	-- Don't skip wrap lines
	{
		{ "n" },
		"j",
		"v:count ? 'j' : 'gj'",
		{ expr = true },
	},
	{
		{ "n" },
		"k",
		"v:count ? 'k' : 'gk'",
		{ expr = true },
	},

	-- Scroll
	{
		{ "n" },
		"<C-d>",
		"v:count ? 'C-d>zz' : (winheight('.') / 2) . '<C-d>zz'",
		{ expr = true },
	},
	{
		{ "n" },
		"<C-u>",
		"v:count ? '<C-u>zz' : (winheight('.') / 2) . '<C-u>zz'",
		{ expr = true },
	},

	-- Treat ctrl+s as normal save command
	{ { "i" }, "<C-s>", "<Esc>:write<CR>i" },
	{ { "n" }, "<C-s>", ":write<CR>" },

	-- Search Replace
	{
		{ "n" },
		"<leader>/r",
		":%s:<C-R><C-w>::g<left><left>",
		{
			desc = "Replace word under cursor",
		},
	},
	{
		{ "n" },
		"<leader>/R",
		":%s:<C-R><C-w>:<C-r><C-w>:<Left>",
		{
			desc = "Replace word under cursor",
		},
	},

	-- Tabs
	{ { "n" }, "<leader>ta", ":$tabnew<CR>", { desc = "tab: open new tab" } },
	{ { "n" }, "<leader>tc", ":tabclose<CR>", { desc = "tab: close current tab" } },
	{ { "n" }, "<A-n>", ":tabn<CR>", { desc = "tab: go to next tab" } },
	{ { "n" }, "<A-p>", ":tabp<CR>", { desc = "tab: go to previous tab" } },
	{ { "n" }, "<leader>to", ":tabonly<CR>", { desc = "tab: close other tabs" } },
	-- -- move current tab to next/previous position
	{ { "n" }, "<leader>tmn", ":+tabmove<CR>", { desc = "tab: move to next tab" } },
	{ { "n" }, "<leader>tmp", ":-tabmove<CR>", { desc = "tab: move to previous tab" } },

	-- Command Mode
	{ { "c" }, "<C-h>", "<Left>" },
	{ { "c" }, "<C-l>", "<Right>" },
	{ { "c" }, "<A-h>", "<S-Left>" },
	{ { "c" }, "<A-l>", "<S-Right>" },
	{ { "c" }, "<C-j>", "<Down>" },
	{ { "c" }, "<C-k>", "<Up>" },
	{ { "c" }, "<C-d>", "<Del>" },
	{ { "c" }, "<C-a>", "<Home>" },
	{ { "c" }, "<C-e>", "<End>" },

	-- Terminal
	{
		{ "n" },
		"<leader>ft",
		function()
			require("aru.terminal")(nil, {})
		end,
	},
	{ { "t" }, "<esc><esc>", "<c-\\><c-n>" },
	{ { "t" }, "<c-/", "<cmd>close<cr>" },

	-- Nop
	{ { "n", "x" }, "<Space>", "<Nop>" },
	{ { "n", "x" }, ",", "<Nop>" },
	{ { "n", "x" }, ";", "<Nop>" },
	{ { "n" }, "q", "<Nop>" },
}

for _, keymap_spec in ipairs(collection) do
	local modes = keymap_spec[1]
	local lhs = keymap_spec[2]
	local rhs = keymap_spec[3]
	local opts = keymap_spec[4] or {}

	log:debug(fmt("Setting keymap: Modes: [%s], LHS: %s", table.concat(modes, ", "), lhs))
	vim.keymap.set(modes, lhs, rhs, opts)
end

return {}
