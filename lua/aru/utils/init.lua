--[[ Main Module

]]
--
local M = {}

local fmt = string.format

function M.invalidate(path, recursive)
	if recursive then
		for key, value in pairs(package.loaded) do
			if key ~= "_G" and value and vim.fn.match(key, path) ~= -1 then
				package.loaded[key] = nil

				require(key)
			end
		end
	else
		package.loaded[path] = nil
		require(path)
	end
end

---Source a lua or vimscript file
---@param path string path relative to the nvim directory
---@param prefix boolean?
function M.source(path, prefix)
	if not prefix then
		vim.cmd(fmt("source %s", path))
	else
		vim.cmd(fmt("source %s/%s", vim.g.vim_dir, path))
	end
end

function M.replace_termcodes(str)
	return vim.api.nvim_replace_termcodes(str, true, true, true)
end

---Determine if a value of any type is empty
---@param item any
---@return boolean
function M.empty(item)
	if not item then
		return true
	end

	local item_type = type(item)
	if item_type == "string" then
		return item == ""
	elseif item_type == "table" then
		return vim.tbl_isempty(item)
	end

	return true
end

---Create an nvim command
---@param name any
---@param opts table?
function M.create_command(name, rhs, opts)
	vim.api.nvim_create_user_command(name, rhs, opts or {})
end

---Create an autocommand
---returns the group ID so that it can be cleared or manipulated.
---@param name string
---@return number
function M.create_augroup(name, commands)
	local id = vim.api.nvim_create_augroup(name, { clear = true })

	for _, autocmd in ipairs(commands) do
		local is_callback = type(autocmd.command) == "function"
		vim.api.nvim_create_autocmd(autocmd.event, {
			group = name,
			pattern = autocmd.pattern,
			desc = autocmd.description,
			callback = is_callback and autocmd.command or nil,
			command = not is_callback and autocmd.command or nil,
			once = autocmd.once,
			nested = autocmd.nested,
			buffer = autocmd.buffer,
		})
	end
	return id
end

--- automatically clear commandline messages after a few seconds delay
--- source: http://unix.stackexchange.com/a/613645
---@return function
function M.clear_commandline(ms)
	--- Track the timer object and stop any previous timers before setting
	--- a new one so that each change waits for 10secs and that 10secs is
	--- deferred each time
	local timer

	return function()
		if timer then
			timer:stop()
		end

		timer = vim.defer_fn(function()
			if vim.fn.mode() == "n" then
				vim.cmd([[echon ""]])
			end
		end, ms)
	end
end

---Find an item in a list
---@generic T
---@param haystack T[]
---@param matcher fun(arg: T):boolean
---@return T
function M.find(haystack, matcher)
	local found
	for _, needle in ipairs(haystack) do
		if matcher(needle) then
			found = needle
			break
		end
	end
	return found
end

---Check if a cmd is executable
---@param e string
---@return boolean
function M.is_executable(e)
	return vim.fn.executable(e) > 0
end

M.skip_foldexpr = {} ---@type table<number,boolean>
local skip_check = assert(vim.uv.new_check())

function M.foldexpr()
	local buf = vim.api.nvim_get_current_buf()

	-- still in the same tick and no parser
	if M.skip_foldexpr[buf] then
		return "0"
	end

	-- don't use treesitter folds for non-file buffers
	if vim.bo[buf].buftype ~= "" then
		return "0"
	end

	-- as long as we don't have a filetype, don't bother
	-- checking if treesitter is available (it won't)
	if vim.bo[buf].filetype == "" then
		return "0"
	end

	local ok = pcall(vim.treesitter.get_parser, buf)

	if ok then
		return vim.treesitter.foldexpr()
	end

	-- no parser available, so mark it as skip
	-- in the next tick, all skip marks will be reset
	M.skip_foldexpr[buf] = true
	skip_check:start(function()
		M.skip_foldexpr = {}
		skip_check:stop()
	end)
	return "0"
end

function M.formatexpr()
	if pcall(require, "conform.nvim") then
		return require("conform").formatexpr()
	end

	return vim.lsp.formatexpr({ timeout_ms = 3000 })
end

return M
