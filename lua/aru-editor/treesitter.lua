return {
	{
		"nvim-treesitter/nvim-treesitter",
		lazy = false,
		version = false,
		branch = "main",
		build = ":TSUpdate",
		config = function(opts)
			require("nvim-treesitter").setup({
				ensure_installed = {
					"core",
					"stable",
				},
			})
		end,
	},
	{
		"windwp/nvim-ts-autotag",
	},
	-- {
	-- 	"aaronik/treewalker.nvim",
	--
	-- 	-- The following options are the defaults.
	-- 	-- Treewalker aims for sane defaults, so these are each individually optional,
	-- 	-- and setup() does not need to be called, so the whole opts block is optional as well.
	-- 	opts = {
	-- 		-- Whether to briefly highlight the node after jumping to it
	-- 		highlight = true,
	--
	-- 		-- How long should above highlight last (in ms)
	-- 		highlight_duration = 250,
	--
	-- 		-- The color of the above highlight. Must be a valid vim highlight group.
	-- 		-- (see :h highlight-group for options)
	-- 		highlight_group = "CursorLine",
	--
	-- 		-- Whether the plugin adds movements to the jumplist -- true | false | 'left'
	-- 		--  true: All movements more than 1 line are added to the jumplist. This is the default,
	-- 		--        and is meant to cover most use cases. It's modeled on how { and } natively add
	-- 		--        to the jumplist.
	-- 		--  false: Treewalker does not add to the jumplist at all
	-- 		--  "left": Treewalker only adds :Treewalker Left to the jumplist. This is usually the most
	-- 		--          likely one to be confusing, so it has its own mode.
	-- 		jumplist = true,
	-- 	},
	-- },
	-- {
	-- 	"nvim-treesitter/nvim-treesitter-textobjects",
	-- 	version = false,
	-- 	branch = "main",
	-- 	config = function(opts)
	-- 		require("nvim-treesitter-textobjects").setup({
	-- 			lookahead = true,
	-- 			selection_modes = {
	-- 				["@parameter.outer"] = "v",
	-- 				["@function.outer"] = "v",
	-- 				["@class.outer"] = "v",
	-- 			},
	-- 			move = { set_jumps = true },
	-- 		})
	--
	-- 		-- keymaps
	-- 		-- You can use the capture groups defined in `textobjects.scm`
	-- 		vim.keymap.set({ "x", "o" }, "af", function()
	-- 			require("nvim-treesitter-textobjects.select").select_textobject(
	-- 				"@function.outer",
	-- 				"textobjects"
	-- 			)
	-- 		end)
	-- 		vim.keymap.set({ "x", "o" }, "if", function()
	-- 			require("nvim-treesitter-textobjects.select").select_textobject(
	-- 				"@function.inner",
	-- 				"textobjects"
	-- 			)
	-- 		end)
	-- 		vim.keymap.set({ "x", "o" }, "ac", function()
	-- 			require("nvim-treesitter-textobjects.select").select_textobject(
	-- 				"@class.outer",
	-- 				"textobjects"
	-- 			)
	-- 		end)
	-- 		vim.keymap.set({ "x", "o" }, "ic", function()
	-- 			require("nvim-treesitter-textobjects.select").select_textobject(
	-- 				"@class.inner",
	-- 				"textobjects"
	-- 			)
	-- 		end)
	-- 		-- You can also use captures from other query groups like `locals.scm`
	-- 		vim.keymap.set({ "x", "o" }, "as", function()
	-- 			require("nvim-treesitter-textobjects.select").select_textobject(
	-- 				"@local.scope",
	-- 				"locals"
	-- 			)
	-- 		end)
	-- 	end,
	-- },
}
