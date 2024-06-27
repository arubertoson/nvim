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
		-- init = function()
		-- 	vim.filetype.add({
		-- 		filename = {
		-- 			["docker-compose.yml"] = "yaml.docker-compose",
		-- 		},
		-- 	})
		-- end,
		opts = {
			servers = {
				zls = {},
			},
		},
	},
}
