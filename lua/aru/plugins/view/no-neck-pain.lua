local function layout_iter(col, winids)
	local type_, value = unpack(col)
	if type_ == "leaf" then
		table.insert(winids, value)
		return winids
	elseif type_ == "row" then
		for _, column in ipairs(value) do
			layout_iter(column, winids)
		end
	else
		for _, val in ipairs(value) do
			layout_iter(val, winids)
		end
	end
	return winids
end

local function flatten_layout(layout)
	local flattned = {}
	if layout[1] == "col" then
		table.insert(flattned, layout_iter(layout, {}))
	else
		for _, col in ipairs(layout[2]) do
			table.insert(flattned, layout_iter(col, {}))
		end
	end
	return flattned
end

local function close_other_windows()
	local windows = vim.api.nvim_tabpage_list_wins(0)
	if #windows == 1 then
		return
	end

	local current_window = vim.api.nvim_get_current_win()
	for _, winids in ipairs(flatten_layout(vim.fn.winlayout())) do
		if vim.tbl_contains(winids, current_window) then
			vim.api.nvim_set_current_win(winids[1])
		else
			for _, winid in ipairs(winids) do
				vim.api.nvim_win_close(winid, true)
			end
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
			debug = false,
			minSideBufferWidth = 10,
			disableOnLastBuffer = false,
			killAllBuffersOnDisable = false,
			fallbackOnBufferDelete = true,
			buffers = {
				colors = {
					background = "#1f1f28",
					blend = -0.25,
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
