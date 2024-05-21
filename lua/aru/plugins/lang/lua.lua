return {

	{
		"williamboman/mason.nvim",
		optional = true,
		opts = { ensure_installed = { "stylua" } },
	},

	{
		"nvim-treesitter/nvim-treesitter",
		optional = true,
		opts = { ensure_installed = {
			"luap",
			"lua",
			"luadoc",
		} },
	},

	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				["lua"] = { "stylua" },
			},
		},
	},

	{
		"folke/lazydev.nvim",
		ft = "lua",
		cmd = "LazyDev",
		opts = {
			library = {
				{ path = "luvit-meta/library", words = { "vim%.uv" } },
				{ path = "LazyVim", words = { "LazyVim" } },
				{ path = "lazy.nvim", words = { "LazyVim" } },
			},
		},
	},
	{ "Bilal2453/luvit-meta", lazy = true },

	{
		"hrsh7th/nvim-cmp",
		optional = true,
		opts = function(_, opts)
			opts.sources = opts.sources or {}
			table.insert(opts.sources, { name = "lazydev", group_index = 0 })
		end,
	},
}
