-----------------------------------------------------------------------------
-- MAPPINGS
-----------------------------------------------------------------------------
-- a mini mapping module for setting keymaps with support for which-key, keys
-- should follow the following:
--  {
--      modes = { "n", "v" },
--      map = "<leader>lh",
--      callback = function() end or "",
--      opts = { opt = value },
--  }
--
local aru = require("aru")
local fmt = string.format
local unpack = table.unpack or unpack

local M = {}

---check if a mapping already exists
---@param lhs string
---@param mode string
---@return boolean
function M.has_map(mode, lhs)
	return vim.fn.maparg(lhs, mode or "n") ~= ""
end

---Create a mapping
---@param mode string
---@param lhs string
---@return string|table<string, any>
function M.map_info(mode, lhs)
	return vim.fn.maparg(lhs, mode or "n", false, true)
end

function M.set(keymap)
	local mode, key, fn, opts = unpack(keymap)
	if type(fn) == "table" then
		local origin, args = unpack(fn)
		assert(type(origin) == "function", "first element needs to be a function")
		assert(type(args) == "table", "second element needs to be parameter table")

		fn = function()
			origin(args)
		end
	end
	-- Assert that we will be able to set the key, it needs to have valid keymap
	-- and command
	assert(key ~= mode, fmt("The lhs (%s) should not be the same as mode for %s", mode, key))
	assert(
		type(fn) == "string" or type(fn) == "function",
		fmt('"rhs" (lhs: %s) should be a function or string', key)
	)

	local log_message = fmt("%s, %s, %s, %s", vim.inspect(mode), key, fn, vim.inspect(opts)):gsub("[\r\n]", "")
	aru.log:debug(log_message)

	vim.keymap.set(mode, key, fn, opts or {})
end

function M.set_maps(keymaps)
	for _, keymap in ipairs(keymaps) do
		-- Warn when we are about to override keymaps
		if type(keymap[1]) == "string" then
			local res = M.map_info(keymap[1], keymap[2])
			if type(res) == "table" and vim.tbl_count(res) > 0 then
				aru.log:warn(fmt("Overriding keymap:%s | %s | %s, ", res.mode, res.lhs, res.desc))
			end
		else
			for _, mode in ipairs(keymap[1]) do
				local res = M.map_info(mode, keymap[2])
				if type(res) == "table" and vim.tbl_count(res) > 0 then
					aru.log:warn(
						fmt("Overriding keymap:%s | %s | %s, ", res.mode, res.lhs, res.desc)
					)
				end
			end
		end

		M.set(keymap)
	end
end

return M
