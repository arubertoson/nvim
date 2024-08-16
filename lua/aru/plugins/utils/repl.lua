local function golden_ratio(is_vertical)
	local ratio = 1.618

	local split_with = vim.o.columns
	if is_vertical then
		split_with = vim.o.lines
	end

	-- We check the current width of the existing window and
	-- overwrite the no-neck-pain config
	return split_with - math.floor(split_with / ratio)
end

return {
	{ "rafcamlet/nvim-luapad", config = true },
	{
		"milanglacier/yarepl.nvim",
		event = "VeryLazy",
		config = function()
			local yarepl = require("yarepl")
			yarepl.setup({
				wincmd = function(bufnr, _)
					local is_vertical = (vim.o.lines / vim.o.columns) > 0.35
					local split_at = golden_ratio(is_vertical)

					local split_cmd = "vsplit"
					if is_vertical then
						split_cmd = "split"
					end

					local concat_cmd = split_at .. " " .. split_cmd
					vim.cmd(concat_cmd)
					vim.api.nvim_set_current_buf(bufnr)
				end,
			})

			vim.api.nvim_create_user_command("REPLSendBuffer", function(opts)
				local id = opts.count
				local name = opts.args
				local current_buffer = vim.api.nvim_get_current_buf()
				local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, -1, false)

				yarepl._send_strings(id, name, current_buffer, lines)
			end, {
				count = true,
				nargs = "?",
				desc = [[
Send entire buffer content to REPL `i` or the REPL that current buffer is attached to.
			]],
			})

			vim.api.nvim_create_user_command("REPLSendTS", function(opts)
				local id = opts.count
				local name = opts.args
				local current_buffer = vim.api.nvim_get_current_buf()

				local parser = vim.treesitter.get_parser(current_buffer)
				local tree = parser:parse()[1]
				local root = tree:root()

				-- Get the node at the cursor position
				local cursor = vim.api.nvim_win_get_cursor(0)
				local node = root:named_descendant_for_range(
					cursor[1] - 1,
					cursor[2],
					cursor[1] - 1,
					cursor[2]
				)

				if node == nil then
					print("no treesitter node found at the cursor position")
					return
				end

				-- Find the closest parent node that's not the root
				while node ~= nil and node:parent() ~= root do
					node = node:parent()
				end

				-- Get the text of the node
				local start_row, start_col, end_row, end_col = node:range()
				local lines = vim.api.nvim_buf_get_text(
					current_buffer,
					start_row,
					start_col,
					end_row,
					end_col,
					{}
				)

				yarepl._send_strings(id, name, current_buffer, lines)
			end, {
				count = true,
				nargs = "?",
				desc = [[
Send the current TreeSitter node (closest to root) to REPL `i` or the REPL that current buffer is attached to.
]],
			})

			vim.api.nvim_set_keymap(
				"n",
				"<Plug>(REPLSendTS)",
				"<CMD>REPLSendTS<CR>",
				{ noremap = true, silent = true }
			)
			vim.api.nvim_set_keymap(
				"n",
				"<Plug>(REPLSendBuffer)",
				"<CMD>REPLSendBuffer<CR>",
				{ noremap = true, silent = true }
			)

			require("aru.utils").create_augroup("aru-repl-group", {
				{
					event = { "FileType" },
					pattern = {
						"python",
						"sh",
						"REPL",
					},
					command = function(args)
						local ft_to_repl = {
							python = "ipython",
							sh = "bash",
						}
						local repl = ft_to_repl[vim.bo.filetype]
						repl = repl and ("-" .. repl) or ""

						-- stylua: ignore
						require("aru.utils.keymaps").set_maps({
							{ { "n" }, "<CR>", "<Plug>(REPLSendTS)", { desc = "Send TreeSitter node to REPL", buffer = args.buffer } },
							{ { "v" }, "<CR>", "<Plug>(REPLSendVisual)", { desc = "Send visual region to REPL", buffer = args.buffer } },
							{ { "n" }, "<localleader>f", "<Plug>(REPLSendOperator)", { desc = "Send current line to REPL", buffer = args.buffer } },
							{ { "n" }, "<localleader>fa", "<Plug>(REPLSendBuffer)", { desc = "Send buffer to REPL", buffer = args.buffer } },

							-- XXX: I can make this into a simple toggle button
							{ { "n" }, "<localleader>rs", string.format("<Plug>(REPLStart%s)", repl), { desc = "Start an REPL", buffer = args.buffer }, },
							{ { "n" }, "<localleader>rh", "<Plug>(REPLHideOrFocus)", { desc = "Hide REPL", buffer = args.buffer} },

							{ { "n" }, "<localleader>rc", "<CMD>REPLCleanup<CR>", { desc = "Clear REPLs.", buffer = args.buffer} },
							{ { "n" }, "<localleader>rq", "<Plug>(REPLClose)", { desc = "Quit REPL", buffer = args.buffer } },
						})
					end,
				},
			})
		end,
	},
}
