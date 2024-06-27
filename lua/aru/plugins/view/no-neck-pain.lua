local function close_other_windows()
	local windows = vim.api.nvim_tabpage_list_wins(0)
	if #windows == 1 then
		return
	end

	local current_win = vim.api.nvim_get_current_win()
	for _, win in ipairs(windows) do
		if win ~= current_win then
			vim.api.nvim_win_close(win, true)
		end
	end
end

local function golden_ratio()
	-- We check the current width of the existing window and
	-- overwrite the no-neck-pain config
	return math.floor(vim.o.columns / 1.618)
end

return {
	{
		"shortcuts/no-neck-pain.nvim",
		version = "*",
		lazy = false,
		opts = {
			debug = true,
			minSideBufferWidth = 10,
			disableOnLastBuffer = false,
			killAllBuffersOnDisable = false,
			fallbackOnBufferDelete = true,
			buffers = {
				colors = {
					background = "rose-pine-moon",
					blend = -0.5,
				},
			},
		},
		config = function(opts)
			require("no-neck-pain").setup(opts.opts)

			require("aru.utils.keymaps").set({
				{ "n" },
				"<leader>wo",
				function()
					local nnp = require("no-neck-pain")

					-- We need to ensure that only one windows before firing the
					-- toggle to ensure that we don't screw up other windows. It's
					-- better to start from a clean slate afterwards.
					close_other_windows()

					-- For some reason if we don't use the normal "command"
					-- routes we have to set the options our selves.
					if nnp.config == nil then
						local opts = require("no-neck-pain.config")
						nnp.config = opts.options
					end

					nnp.config.width = golden_ratio()
					nnp.toggle()
				end,
				{
					desc = "NoNeckPain Toggle",
				},
			})

			-- To keep the window nice and centered in the correct ratio we add a little
			-- sweet autocmd to operate on the window resize.
			require("aru.utils").create_augroup("no-neck-pain-resize", {
				{
					event = { "VimResized" },
					command = function()
						local nnp = require("no-neck-pain")

						if nnp.state == nil then
							return
						end

						nnp.resize(golden_ratio())
					end,
				},
			})
		end,
	},
}
