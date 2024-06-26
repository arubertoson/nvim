local M = {}

function M.find_max_column(bufnr)
	local max_col = 0
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for _, line in ipairs(lines) do
		local col = #line
		if col > max_col then
			max_col = col
		end
	end
	return max_col
end

return M
