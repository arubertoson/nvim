local M = {}

local log = require("aru").get_logger("AruLLM", "INFO")

local err, sllm = pcall(require, "sllm")
if not err then
	log:info("Couldn't import sllm.nvim")
end

local Backend = require("sllm.backend.llm")
local CtxMan = require("sllm.context_manager")
local JobMan = require("sllm.job_manager")
local Ui = require("sllm.ui")
local Utils = require("sllm.utils")

local input = require("snacks.input").input
local notify = require("snacks.notify").notify

--- Ask the LLM with a prompt from the user.
---@return nil
function M.ask_llm_async()
	if Utils.is_mode_visual() then
		sllm.add_sel_to_ctx()
	end
	input({ prompt = "Prompt: " }, function(user_input)
		if user_input == "" then
			notify("[sllm] no prompt provided.", vim.log.levels.INFO)
			return
		end

		local ctx = CtxMan.get()
		local prompt = CtxMan.render_prompt_ui(user_input)
		Ui.append_to_llm_buffer({ "", "> 💬 Prompt:", "" })
		Ui.append_to_llm_buffer(vim.split(prompt, "\n", { plain = true }))
		Ui.start_loading_indicator()

		local cmd = Backend.llm_cmd(
			prompt,
			true,
			true,
			sllm.state.selected_model,
			ctx.fragments,
			ctx.tools,
			ctx.functions,
			"ask"
		)
		state.continue = true

		local first_line = false
		JobMan.start(
			cmd,
			---@param line string
			function(line)
				if not first_line then
					Ui.stop_loading_indicator()
					Ui.append_to_llm_buffer({ "", "> 🤖 Response", "" })
					first_line = true
				end
				Ui.append_to_llm_buffer({ line })
			end,
			---@param exit_code integer
			function(exit_code)
				Ui.stop_loading_indicator()
				if not first_line then
					Ui.append_to_llm_buffer({ "", "> 🤖 Response", "" })
					local msg = exit_code == 0 and "(empty response)"
						or string.format("(failed or canceled: exit %d)", exit_code)
					Ui.append_to_llm_buffer({ msg })
				end
				notify("[sllm] done ✅ exit code: " .. exit_code, vim.log.levels.INFO)
				Ui.append_to_llm_buffer({ "" })
				if config.reset_ctx_each_prompt then
					CtxMan.reset()
				end
			end
		)
	end)
end

return M
