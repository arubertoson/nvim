--
--	Repo URL: https://github.com/arubertoson/vimfiles
--	Author: Marcus Albertsson
--
--
local Autogrps = {}

local aru = require("aru")
local utils = require("aru.utils")

local fn = vim.fn
local api = vim.api
local fmt = string.format
local contains = vim.tbl_contains
local map = vim.keymap.set

----------------------------------------------------------------------------------------------------
-- HLSEARCH
----------------------------------------------------------------------------------------------------
--[[
In order to get hlsearch working the way I like i.e. on when using /,?,N,n,*,#, etc. and off when
When I'm not using them, I need to set the following:
The mappings below are essentially faked user input this is because in order to automatically turn off
the search highlight just changing the value of 'hlsearch' inside a function does not work
read `:h nohlsearch`. So to have this work I check that the current mouse position is not a search
result, if it is we leave highlighting on, otherwise I turn it off on cursor moved by faking my input
using the expr mappings below.

This is based on the implementation discussed here:
https://github.com/neovim/neovim/issues/5581
--]]

map({ "n", "v", "o", "i", "c" }, "<Plug>(StopHL)", "execute('nohlsearch')[-1]", { expr = true })

local function stop_hl()
	if vim.v.hlsearch == 0 or api.nvim_get_mode().mode ~= "n" then
		return
	end

	api.nvim_feedkeys(utils.replace_termcodes("<Plug>(StopHL)"), "m", false)
end

local function hl_search()
	local col = api.nvim_win_get_cursor(0)[2]
	local curr_line = api.nvim_get_current_line()
	local ok, match = pcall(fn.matchstrpos, curr_line, fn.getreg("/"), 0)
	if not ok then
		return vim.notify(match, "error", { title = "HL SEARCH" })
	end

	-- if the cursor is in a search result, leave highlighting on
	local _, p_start, p_end = unpack(match)
	if col < p_start or col > p_end then
		stop_hl()
	end
end

local smart_close_filetypes = {
	"help",
	"git-status",
	"git-log",
	"gitcommit",
	"notify",
	"neotest-output",
	"neotest-summary",
	"neotest-output-panel",
	"checkhealth",
	"dbui",
	"fugitive",
	"fugitiveblame",
	"LuaTree",
	"log",
	"tsplayground",
	"qf",
	"lspinfo",
	"NvimTree",
}

local smart_close_buftypes = {} -- Don't include no file buffers as diff buffers are nofile

local function smart_close()
	if fn.winnr("$") ~= 1 then
		api.nvim_win_close(0, true)
	end
end

local function should_show_cursorline()
	return vim.bo.buftype ~= "terminal"
		and not vim.wo.previewwindow
		and vim.wo.winhighlight == ""
		and vim.bo.filetype ~= ""
end

local save_excluded = {
	"NvimTree",
}

local function can_save()
	return utils.empty(vim.bo.buftype)
		and not utils.empty(vim.bo.filetype)
		and vim.bo.modifiable
		and not vim.tbl_contains(save_excluded, vim.bo.filetype)
end

local number_exclude_ft = { "NvimTree", "markdown", "telekasten", "dbui", "dbout" }
local number_exclude_bt = { "terminal" }

local augroups = {
	VimIncSearchHL = {
		{
			event = { "CursorMoved" },
			command = function()
				hl_search()
			end,
		},
		{
			event = { "InsertEnter" },
			command = function()
				stop_hl()
			end,
		},
		{
			event = { "OptionSet" },
			pattern = { "hlsearch" },
			command = function()
				vim.schedule(function()
					vim.cmd("redrawstatus")
				end)
			end,
		},
	},
	ClearCommandMessage = {
		{
			event = { "CmdlineLeave", "CmdlineChanged" },
			pattern = { ":" },
			command = utils.clear_commandline(5000),
		},
	},
	SmartClose = {
		{
			-- Auto open grep quickfix window
			event = { "QuickFixCmdPost" },
			pattern = { "*grep*" },
			command = "cwindow",
		},
		{
			-- Close certain filetypes by pressing q.
			event = { "FileType" },
			pattern = "*",
			command = function()
				local is_unmapped = fn.hasmapto("q", "n") == 0

				local is_eligible = is_unmapped
					or vim.wo.previewwindow
					or contains(smart_close_buftypes, vim.bo.buftype)
					or contains(smart_close_filetypes, vim.bo.filetype)

				if is_eligible then
					require("aru.utils.keymaps").set({
						"n",
						"q",
						smart_close,
						{ buffer = 0, nowait = true },
					})
				end
			end,
		},
		{
			-- Close quick fix window if the file containing it was closed
			event = { "BufEnter" },
			pattern = "*",
			command = function()
				if fn.winnr("$") == 1 and vim.bo.buftype == "quickfix" then
					api.nvim_buf_delete(0, { force = true })
				end
			end,
		},
		{
			-- automatically close corresponding loclist when quitting a window
			event = { "QuitPre" },
			pattern = "*",
			nested = true,
			command = function()
				if vim.bo.filetype ~= "qf" then
					vim.cmd("silent! lclose")
				end
			end,
		},
	},
	Cursorline = {
		{
			event = { "BufEnter" },
			pattern = { "*" },
			command = function()
				if should_show_cursorline() then
					vim.wo.cursorline = true
				end
			end,
		},
		{
			event = { "BufLeave" },
			pattern = { "*" },
			command = function()
				vim.wo.cursorline = false
			end,
		},
	},
	Utilities = {
		{
			event = { "BufWritePre", "FileWritePre" },
			pattern = { "*" },
			command = "silent! call mkdir(expand('<afile>:p:h'), 'p')",
		},
		{
			event = { "BufLeave" },
			pattern = { "*" },
			command = function()
				if can_save() then
					vim.cmd("silent! update")
				end
			end,
		},
	},
	AruNumbers = {
		{
			event = { "WinEnter", "BufEnter" },
			pattern = { "*?" },
			command = function()
				if
					vim.tbl_contains(number_exclude_ft, vim.bo.filetype)
					or vim.tbl_contains(number_exclude_bt, vim.bo.buftype)
				then
					return nil
				end

				vim.wo.number = true
				vim.wo.relativenumber = true
			end,
		},
		{
			event = { "WinLeave", "BufLeave" },
			pattern = { "*?" },
			command = function()
				if
					vim.tbl_contains(number_exclude_ft, vim.bo.filetype)
					or vim.tbl_contains(number_exclude_bt, vim.bo.buftype)
				then
					return nil
				end

				vim.wo.number = true
				vim.wo.relativenumber = false
			end,
		},
	},

	-- For general other stuff
	AruVimAuRc = {
		{
			event = { "TextYankPost" },
			pattern = { "*" },
			command = function()
				vim.highlight.on_yank({
					on_visual = false,
					higroup = "IncSearch",
					timeout = 100,
				})
			end,
		},
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
	},
}

-----------------------------------------------------------------------------//
-- Utils
-----------------------------------------------------------------------------//

function Autogrps.setup()
	aru.log:debug("Setting up custom augroups")

	for grp, cmds in pairs(augroups) do
		aru.log:debug(fmt("Creating commands for group %s", grp))

		utils.create_augroup(grp, cmds)
	end
end

return Autogrps
