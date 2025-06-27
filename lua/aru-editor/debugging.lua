local log = require("aru.logging").get_logger("AruDAP", "INFO")

return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			"rcarriga/nvim-dap-ui",
			"nvim-neotest/nvim-nio",
			"mfussenegger/nvim-dap-python",
		},
		version = "*",
		config = function()
			local dap = require("dap")
			local ui = require("dapui")
			local py = require("dap-python")

			ui.setup()
			py.setup("python")

			vim.keymap.set("n", "<localleader>gb", dap.toggle_breakpoint)
			vim.keymap.set("n", "<localleader>gc", dap.continue)
			vim.keymap.set("n", "<localleader>go", dap.step_over)
			vim.keymap.set("n", "<localleader>gi", dap.step_into)
			vim.keymap.set("n", "<localleader>gO", dap.step_out)

			vim.keymap.set("n", "<localleader>gq", dap.terminate)
			vim.keymap.set("n", "<localleader>gu", ui.toggle)

			dap.listeners.before.attach.dapui_config = function()
				ui.open()
			end
			dap.listeners.before.launch.dapui_config = function()
				ui.open()
			end
			dap.listeners.before.event_terminated.dapui_config = function()
				ui.close()
			end
			dap.listeners.before.event_exited.dapui_config = function()
				ui.close()
			end
		end,
	},
}
