-- local function set_golden_ratio_width()
--     local golden_ratio = 1.618
--     local height = vim.api.nvim_win_get_height(0)
--     local golden_width = math.floor(height * golden_ratio)
--     vim.api.nvim_win_set_width(0, golden_width)
--     print("Golden Ratio Width: " .. golden_width)
-- end
--

return {
	{
		"shortcuts/no-neck-pain.nvim",
		cmd = { "NoNeckPain" },
		-- opts = {
		-- 	width = function()
		--
		-- 	end
		-- },
		-- config = function()
		-- 	vim.keymap.set()
		-- end,
	},
}
