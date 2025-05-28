local M = setmetatable({}, {
	__call = function(m, ...)
		return m.open(...)
	end,
})

local terminals = {}

function M.open(cmd, opts)
	opts = vim.tbl_deep_extend("force", {
		ft = "aruterm",
		size = { width = 0.9, height = 0.9 },
		backdrop = not cmd and 100 or nil,
	}, opts or {}, { persistent = true })

	local termkey = vim.inspect({ cmd = cmd or "shell", cwd = opts.cwd, env = opts.env, count = vim.v.count1 })

	if terminals[termkey] and terminals[termkey]:buf_valid() then
		terminals[termkey]:toggle()
	else
		terminals[termkey] = require("lazy.util").float_term(cmd, opts)
		local buf = terminals[termkey].buf
		vim.b[buf].aruterm_cmd = cmd

		vim.keymap.set("n", "gf", function()
			local f = vim.fn.findfile(vim.fn.expand("<cfile>"))
			if f ~= "" then
				vim.cmd("close")
				vim.cmd("e " .. f)
			end
		end, { buffer = buf })

		{
			event = { "TermOpen", "BufWinEnter", "BufEnter" },
			pattern = { "term://*" },
			command = function()
				vim.cmd("startinsert")
			end,
		},
		{
			event = { "TermOpen" },
			pattern = { "*" },
			command = function()
				vim.wo.list = false
				vim.wo.number = false
				vim.wo.relativenumber = false
				vim.wo.signcolumn = "no"
				vim.wo.cursorline = false
			end,
		},
	end

	return terminals[termkey]
end

return M
