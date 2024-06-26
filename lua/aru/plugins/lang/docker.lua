return {
	{
		"nvim-treesitter/nvim-treesitter",
		optional = true,
		init = function()
			vim.treesitter.language.register("yaml", "yaml.docker-compose")
		end,
		opts = { ensure_installed = { "dockerfile" } },
	},
	{
		"williamboman/mason.nvim",
		optional = true,
		opts = {
			ensure_installed = {
				"hadolint",
				"docker-compose-language-service",
				"dockerfile-language-server",
			},
		},
	},
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				dockerfile = { "hadolint" },
			},
		},
	},
	{
		"neovim/nvim-lspconfig",
		optional = true,
		init = function()
			vim.filetype.add({
				filename = {
					["docker-compose.yml"] = "yaml.docker-compose",
				},
			})
		end,
		opts = {
			servers = {
				dockerls = {},
				docker_compose_language_service = {},
			},
		},
	},
}
