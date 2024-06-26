return {
	{
		"ThePrimeagen/harpoon",
		branch = "harpoon2",
		lazy = true,
		init = function()
			vim.keymap.set("n", "<localleader>i", function()
				require("harpoon"):list():add()
			end)
			vim.keymap.set("n", "<localleader>e", function()
				require("harpoon").ui:toggle_quick_menu(require("harpoon"):list())
			end)

			for _, idx in ipairs({ "f", "j", "d", "k" }) do
				vim.keymap.set("n", string.format("<localleader>%s", idx), function()
					require("harpoon"):list():select(idx)
				end)
			end
		end,
		config = function()
			require("harpoon"):setup()
		end,
	},
}
