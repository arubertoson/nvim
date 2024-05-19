return {
  {
    "nvim-treesitter/nvim-treesitter",
	--    dependencies = {
	-- "tjdevries/tree-sitter-lua"
	--    },
    build = ":TSUpdate",
    branch = "main",
    lazy = false,
    config = function()
      require("custom.treesitter").setup()
    end,
  },
}
