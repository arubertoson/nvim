return {
	{
		"nvim-treesitter/nvim-treesitter",
		optional = true,
		opts = { ensure_installed = { "zig" } },
	},
	{
		"williamboman/mason.nvim",
		optional = true,
		opts = {
			ensure_installed = {
				"zls",
			},
		},
	},
	{
		"neovim/nvim-lspconfig",
		optional = true,
		opts = {
			servers = {
				zls = {},
			},
		},
	},
}
