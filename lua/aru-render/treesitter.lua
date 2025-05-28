return {
	{
		"nvim-treesitter/nvim-treesitter",
		lazy = false,
		version = false,
		branch = "main",
		build = ":TSUpdate",
		config = function(opts)
			-- Set fold options related to treesitter
			vim.opt.foldmethod = "expr"
			vim.opt.foldexpr = "v:lua.require'aru.utils'.foldexpr()"

			require("nvim-treesitter").setup({
				ensure_installed = {
					"core", "stable"
				}
			})

			require("aru.utils").create_augroup("aru-treesitter-grp", {
				{
					event = { "FileType" },
					pattern = "*",
					command = function()
						local ok = pcall(vim.treesitter.start)
						if not ok then
							return
						end

						vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"

						vim.wo.foldmethod = "expr"
						vim.wo.foldenable = false
					end,
				},
			})
		end,
	},
	{
		"windwp/nvim-ts-autotag",
		dependencies = { "nvim-treesitter" }
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		version = false,
		branch = "main",
		dependencies = { "nvim-treesitter" },
		config = function(opts)
			require("nvim-treesitter-textobjects").setup({
				lookahead=true,
				selection_modes = {
					["@parameter.outer"] = "v",
					["@function.outer"] = "v",
					["@class.outer"] = "v",
				},
				move = { set_jumps = true },
			})

			-- keymaps
			-- You can use the capture groups defined in `textobjects.scm`
			vim.keymap.set({ "x", "o" }, "af", function()
			  require "nvim-treesitter-textobjects.select".select_textobject("@function.outer", "textobjects")
			end)
			vim.keymap.set({ "x", "o" }, "if", function()
			  require "nvim-treesitter-textobjects.select".select_textobject("@function.inner", "textobjects")
			end)
			vim.keymap.set({ "x", "o" }, "ac", function()
			  require "nvim-treesitter-textobjects.select".select_textobject("@class.outer", "textobjects")
			end)
			vim.keymap.set({ "x", "o" }, "ic", function()
			  require "nvim-treesitter-textobjects.select".select_textobject("@class.inner", "textobjects")
			end)
			-- You can also use captures from other query groups like `locals.scm`
			vim.keymap.set({ "x", "o" }, "as", function()
			  require "nvim-treesitter-textobjects.select".select_textobject("@local.scope", "locals")
			end)

			-- swaps
			vim.keymap.set("n", "<leader>a", function()
			  require("nvim-treesitter-textobjects.swap").swap_next "@parameter.inner"
			end)
			vim.keymap.set("n", "<leader>A", function()
			  require("nvim-treesitter-textobjects.swap").swap_previous "@parameter.outer"
			end)
		end
	},
}
