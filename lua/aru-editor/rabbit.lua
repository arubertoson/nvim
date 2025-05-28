local git_cache = {}

---@type string?
local dir = "/home/macke/dev/github.com/VoxelPrismatic/rabbit.nvim"
if vim.uv.fs_stat(tostring(dir)) == nil then
	dir = nil
end

return { ---@type LazyPluginSpec
	"voxelprismatic/rabbit.nvim",
	dir = dir,
	branch = "rewrite",
	lazy = false,
	cmd = "Rabbit",
	---@diagnostic disable-next-line: missing-fields
	opts = { ---@type Rabbit.Config
		keys = {
			switch = "<leader>r",
		},
		plugins = {
			carrot = {
				name = "carrot",
				keys = {
					insert = "<leader>ri",
				},
			},
		},
	},
	config = function(self)
		require("rabbit").setup(self.opts)
		local select = require("rabbit.util.scripts").bind_select

		-- require("which-key").add({
		-- 	{ "<leader>t", name = "Rabbitscope" },
		-- })

		-- stylua: ignore start
		-- vim.keymap.set( "n", "<localleader>f", select("carrot", 1, { idx = 1, action = "select" }), { desc = "Rabbit: Jump to Carrot item 1" })
		-- vim.keymap.set( "n", "<localleader>r", select("carrot", 2, { idx = 2, action = "select" }), { desc = "Rabbit: Jump to Carrot item 2" })
		-- vim.keymap.set( "n", "<localleader>t", select("carrot", 3, { idx = 3, action = "select" }), { desc = "Rabbit: Jump to Carrot item 2" })
		-- vim.keymap.set( "n", "<localleader>g", select("carrot", 4, { idx = 4, action = "select" }), { desc = "Rabbit: Jump to Carrot item 2" })
		-- stylua: ignore end

		vim.keymap.set("n", "<leader>tg", select("forage", 1, { idx = 1, action = "rename" }), { desc = "rg" })
		vim.keymap.set("n", "<leader>tf", select("forage", 2, { idx = 1, action = "rename" }), { desc = "fzr" })
	end,
}
