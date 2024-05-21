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
--      label = "description",
--  }
--

local M = {}

local aru = require("aru")

local unpack = table.unpack or unpack
local fmt = string.format

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
	local mode, key, func, desc = unpack(keymap)
	if type(func) == "table" then
		local origin, args = unpack(func)
		assert(type(origin) == "function", "first element needs to be a function")
		assert(type(args) == "table", "second element needs to be parameter table")

		func = function()
			origin(args)
		end
	end
	-- Assert that we will be able to set the key, it needs to have valid keymap
	-- and command
	assert(key ~= mode, fmt("The lhs (%s) should not be the same as mode for %s", mode, key))
	assert(
		type(func) == "string" or type(func) == "function",
		fmt('"rhs" (lhs: %s) should be a function or string', key)
	)

	vim.keymap.set(mode, key, func, desc or {})
end

function M.set_maps(keymaps)
	for _, keymap in ipairs(keymaps) do
		aru.log:debug(fmt("%s:%s:%s:%s", keymap[1], keymap[2], keymap[3], keymap[4]))

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
