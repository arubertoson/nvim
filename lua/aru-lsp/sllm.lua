return {

	{
		"mozanunal/sllm.nvim",
		dependencies = {
			"folke/snacks.nvim",
		},
		config = function()
			require("sllm").setup({
				window_type = "floating",
				pick_func = require("snacks.picker").select,
				notify = require("snacks.notifier").notify,
				input = require("snacks.input").input,
			})
		end,
	},
}
