---@module "aru.core.smartjmp"
---@brief Session-aware jump history tuned for Neovim nightly
---@description
--- SmartJmp exists as the lightweight middle ground between the jumplist and
--- manual marks. It remembers the views you actually care about, ignores noise,
--- and survives a whole session.
---
--- We treat navigation as bursts, fast hops stay invisible while real leaps
--- are captured after a debounce window. The history feels intentional rather
--- than mechanical.

--- The module favors observable buffer paths over ephemeral numbers to keep
--- continuity across reloads, clamps history to a tiny ring to stay cache-hot,
--- and leans on LuaJIT- friendly data structures so you never notice it’s
--- watching.

local log = require("aru.log")

local default_config = {
	debounce_ms = 500,
	major_move_lines = 7,
	max_views_per_buffer = 15,
	---@type string[]
	exclude_filetypes = { "oil", "fzf" },
	exclude_buftypes = {
		"help",
		"nofile",
		"quickfix",
		"terminal",
		"prompt",
		"acwrite",
	},
	augroup_id = vim.api.nvim_create_augroup("aru_smartjmp", { clear = true }),
	namespace = vim.api.nvim_create_namespace("aru_smartjmp"),
}

---@class SmartJmp.Module
---@field private states table<string, SmartJmp.JumpState>
---@field private config SmartJmp.Config
local M = {
	states = {},
	config = vim.tbl_extend("force", {}, default_config),
}

---@class SmartJmp.Config
---@field debounce_ms number
---@field major_move_lines number
---@field max_views_per_buffer number
---@field exclude_filetypes string[]
---@field exclude_buftypes string[]
---@field augroup_id number
---@field namespace  number

---@class SmartJmp.View :   vim.fn.winrestview.dict
---@field lnum        number
---@field col         number
---@field coladd      number
---@field curswant    number
---@field leftcol     number
---@field topline     number
---@field botline     number
---@field topfill     number
---@field skipcol     number
---@field extmark_id  number

---@return SmartJmp.View
local function capture_view()
	return vim.tbl_extend("force", {}, vim.fn.winsaveview(), { botline = vim.fn.line("w$") })
end

---@param origin SmartJmp.View
---@param current SmartJmp.View
---@return boolean
local function is_major_move(origin, current)
	if math.abs(origin.lnum - current.lnum) > M.config.major_move_lines then
		return true
	end

	-- We check whether the current cursor position is within the original viewport
	if origin.botline < current.lnum or current.lnum < origin.topline then
		return true
	end

	return false
end

---@class SmartJmp.Burst
---@field origin   SmartJmp.View?
---@field debounce uv.uv_timer_t

---@class SmartJmp.JumpState
---@field buf_name  string
---@field index     number
---@field buf_index number
---@field moving    boolean
---@field views SmartJmp.View[]
---@field burst SmartJmp.Burst?
local JumpState = {}
JumpState.__index = JumpState

---@param buf_index number
---@return SmartJmp.JumpState
function JumpState:new(buf_index)
	local buffer_name = vim.api.nvim_buf_get_name(buf_index)
	assert(type(buffer_name) == "string")
	assert(buffer_name ~= "")

	local self = setmetatable({}, JumpState)
	self.buf_name = buffer_name
	self.buf_index = buf_index
	self.index = 0
	self.views = {}

	-- If we can't get a valid timer here we just explode the whole thing,
	-- the app state is broken.
	local timer = vim.uv.new_timer()
	assert(timer)
	self.burst = { debounce = timer }
	return self
end

function JumpState:stop_burst()
	local t = self.burst.debounce
	if t and not t:is_closing() then
		t:stop()
	end
	self.burst.origin = nil
end

function JumpState:norm()
	if self.index == #self.views then
		return
	end

	local buf_valid = self.buf_index and vim.api.nvim_buf_is_valid(self.buf_index)

	for idx, view in ipairs(self.views) do
		if idx > self.index then
			if buf_valid and view.extmark_id then
				vim.api.nvim_buf_del_extmark(self.buf_index, M.config.namespace, view.extmark_id)
			end

			table.remove(self.views, idx)
		end
	end

	assert(self.index == #self.views)
end

---@param view SmartJmp.View
function JumpState:add(view)
	self:norm()

	if not self.buf_index or not vim.api.nvim_buf_is_valid(self.buf_index) then
		log:warn(("add: invalid buffer for %s"):format(self.buf_name))
		return
	end

	-- Guard against duplicates, we are doing a naive line check--that is enough
	-- in almost all cases to check for a "duplicate".
	local last = self.views[#self.views]
	if
		last
		and last.lnum == view.lnum
		and last.col == view.col
		and last.topline == view.topline
		and last.leftcol == view.leftcol
		and last.skipcol == view.skipcol
	then
		return
	end

	local line = vim.api.nvim_get_current_line()
	local row = view.lnum - 1
	view.extmark_id = vim.api.nvim_buf_set_extmark(self.buf_index, M.config.namespace, row, view.col, {
		right_gravity = true,
		end_row = row,
		end_col = math.min(#line, view.col + 1),
	})

	table.insert(self.views, view)
	if #self.views > M.config.max_views_per_buffer then
		table.remove(self.views, 1)
	end

	self.index = #self.views
end

function JumpState:restore()
	self:stop_burst()
	self.moving = true

	if not self.buf_index or not vim.api.nvim_buf_is_valid(self.buf_index) then
		log:warn(("restore: invalid buffer for %s"):format(self.buf_name))
		self.moving = false
		return
	end

	local view = self.views[self.index]
	if not view then
		self.moving = false
		return
	end

	if view.extmark_id then
		local ok, pos =
			pcall(vim.api.nvim_buf_get_extmark_by_id, self.buf_index, M.config.namespace, view.extmark_id, {})
		if ok and pos[1] then
			view.lnum = pos[1] + 1
			view.col = pos[2]
		else
			log:warn(("restore: extmark %d deleted for %s"):format(view.extmark_id, self.buf_name))
		end
	end

	vim.fn.winrestview(view)

	local highlight_id = vim.api.nvim_buf_set_extmark(self.buf_index, M.config.namespace, view.lnum - 1, 0, {
		end_line = view.lnum,
		hl_group = "IncSearch",
		hl_eol = true,
		priority = 1000,
	})

	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(self.buf_index) then
			vim.api.nvim_buf_del_extmark(self.buf_index, M.config.namespace, highlight_id)
		end
	end, 150)

	self.moving = false
end

function JumpState:prev()
	local old = self.index
	self.index = math.max(1, self.index - 1)
	if self.index == old then
		return
	end

	log:trace(("prev: jump %s idx=%d"):format(self.buf_name, self.index))

	self:restore()
end

function JumpState:next()
	local old = self.index
	self.index = math.min(#self.views, self.index + 1)
	if self.index == old then
		return
	end

	log:trace(("next: jump %s idx=%d"):format(self.buf_name, self.index))

	self:restore()
end

---@param buf_index number
local function create_cursor_move_autocmd(buf_index)
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = M.config.augroup_id,
		buffer = buf_index,
		desc = "",
		callback = function(ev)
			local state = M.states[vim.api.nvim_buf_get_name(ev.buf)]
			if not state or state.moving then
				return
			end

			if not state.burst.origin then
				state.burst.origin = state.views[state.index]
			end

			local timer = state.burst.debounce

			if timer:is_active() then
				timer:stop()
			end

			timer:start(M.config.debounce_ms, 0, function()
				vim.schedule(function()
					local state = M.states[vim.api.nvim_buf_get_name(ev.buf)]

					local b = assert(state.burst)
					if not b and not b.origin then
						state:stop_burst()
						return
					end

					local current = capture_view()
					if not b.origin or is_major_move(b.origin, current) then
						state:add(current)
					end

					state:stop_burst()
				end)
			end)
		end,
	})
end

---@param buf_index number
local function create_buf_wipeout_autocmd(buf_index)
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = M.config.augroup_id,
		buffer = buf_index,
		desc = "Cleanup our buffer timer when a buffer get's wiped. We maintain all state throughout the session.",
		callback = function(ev)
			local state = M.states[vim.api.nvim_buf_get_name(ev.buf)]
			if not state then
				return
			end

			if state.burst and state.burst.debounce then
				local t = state.burst.debounce
				if t then
					t:stop()
					t:close()
				end
			end
			state.burst.origin = nil
			state.burst.debounce = nil
			state.buf_index = nil

			for _, view in ipairs(state.views) do
				view.extmark_id = nil
			end
		end,
	})
end

---@param buf_index number
local function on_buf_enter(buf_index)
	local buf_name = vim.api.nvim_buf_get_name(buf_index)
	local state = M.states[buf_name]

	if not state then
		-- We go fairly hard in our exclusion, we don't want to mess with buffers
		-- that shouldn't have any jump points.
		local ft = vim.api.nvim_get_option_value("filetype", { buf = buf_index })
		local bt = vim.api.nvim_get_option_value("buftype", { buf = buf_index })
		if
			vim.tbl_contains(M.config.exclude_filetypes, ft)
			or vim.tbl_contains(M.config.exclude_buftypes, bt)
			or buf_name == ""
		then
			log:debug(("on_buf_enter: excluded %s"):format(buf_name))
			return
		end

		state = JumpState:new(buf_index)
		M.states[state.buf_name] = state

		log:debug(("on_buf_enter: attached %s:%d"):format(buf_name, state.index))

		create_cursor_move_autocmd(buf_index)
		create_buf_wipeout_autocmd(buf_index)
	else
		log:debug(("on_buf_enter: restore buffer state for %s:%d"):format(buf_name, state.index))

		-- we need to restore the state and its views when we reattach the
		-- buffer. If the buffer was wiped, we've retained the veiws but all
		-- extmarks are gone and needs to be recreated.
		if state.buf_index == buf_index and buf_index and vim.api.nvim_buf_is_valid(buf_index) then
			return
		end

		if state.burst and not state.burst.debounce then
			state.burst.debounce = assert(vim.uv.new_timer())
		end

		state.buf_index = buf_index

		local line_count = vim.api.nvim_buf_line_count(buf_index)
		local max_row = math.max(line_count - 1, 0)

		for _, view in ipairs(state.views) do
			view.extmark_id = nil

			local row = math.min(math.max(view.lnum - 1, 0), max_row)
			local line = vim.api.nvim_buf_get_lines(buf_index, row, row + 1, false)[1] or ""
			local col = math.min(math.max(view.col, 0), #line)

			view.extmark_id = vim.api.nvim_buf_set_extmark(buf_index, M.config.namespace, row, col, {
				right_gravity = true,
				end_row = row,
				end_col = col + 1,
			})
		end

		state:restore()
		return
	end
end

function M.next()
	local buf = vim.api.nvim_get_current_buf()
	local state = M.states[vim.api.nvim_buf_get_name(buf)]
	if not state then
		return
	end

	state:next()
end

function M.prev()
	local buf = vim.api.nvim_get_current_buf()
	local state = M.states[vim.api.nvim_buf_get_name(buf)]
	if not state then
		return
	end

	state:prev()
end

function M.reset()
	log:trace(("reset: states for %d buffers"):format(#M.states))

	for _, state in pairs(M.states) do
		if state.burst and state.burst.debounce then
			state.burst.debounce:stop()
			state.burst.debounce:close()
		end

		vim.api.nvim_clear_autocmds({
			buffer = state.buf_index,
			group = M.config.augroup_id,
		})
	end

	M.states = {}

	on_buf_enter(vim.api.nvim_get_current_buf())
end

function M.setup()
	vim.api.nvim_create_autocmd("BufEnter", {
		group = M.config.augroup_id,
		desc = "",
		callback = function(ev)
			on_buf_enter(ev.buf)
		end,
	})
end

return M
