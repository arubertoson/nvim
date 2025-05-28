local helper = require("aru.helper")
local log = require("aru.logging").get_logger("AruAutocmds", "INFO") -- Explicitly setting logger name and level

local fn = vim.fn
local api = vim.api
local fmt = string.format
local contains = vim.tbl_contains
local map = vim.keymap.set

----------------------------------------------------------------------------------------------------
-- HLSEARCH
----------------------------------------------------------------------------------------------------

map({ "n", "v", "o", "i", "c" }, "<Plug>(StopHL)", "execute('nohlsearch')[-1]", { expr = true })

function stop_hl()
	if vim.v.hlsearch == 0 or api.nvim_get_mode().mode ~= "n" then
		return
	end

	local str = vim.api.nvim_replace_termcodes("<Plug>(StopHL)", true, true, true)
	api.nvim_feedkeys(str, "m", false)
end

local number_exclude_ft = { "markdown", "telekasten", "dbui", "dbout", "oil" }
local number_exclude_bt = { "terminal" }

local augroups = {
	VimIncSearchHL = {
		{
			event = { "CursorMoved" },
			command = function()
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
			end,
		},
		{
			event = { "InsertEnter" },
			command = function() end,
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
			command = helper.clear_commandline(5000),
		},
	},
	SmartClose = {
		{
			-- Close certain filetypes by pressing q.
			event = { "FileType" },
			pattern = "*",
			command = function()
				local smart_close_filetypes = {
					"help",
					"git-status",
					"git-log",
					"gitcommit",
					"notify",
					"checkhealth",
					"dbui",
					"log",
					"qf",
					"lspinfo",
				}

				local smart_close_buftypes = {} -- Don't include no file buffers as diff buffers are nofile

				local function smart_close()
					if fn.winnr("$") ~= 1 then
						api.nvim_win_close(0, true)
					end
				end

				local is_unmapped = fn.hasmapto("q", "n") == 0

				local is_eligible = is_unmapped
					or vim.wo.previewwindow
					or contains(smart_close_buftypes, vim.bo.buftype)
					or contains(smart_close_filetypes, vim.bo.filetype)

				if is_eligible then
					vim.keymap.set(
						"n",
						"q",
						smart_close,
						{ buffer = 0, nowait = true, silent = true }
					)
				end
			end,
		},
	},
	Cursorline = {
		{
			event = { "BufEnter" },
			pattern = { "*" },
			command = function()
				local function should_show_cursorline()
					return vim.bo.buftype ~= "terminal"
						and not vim.wo.previewwindow
						and vim.wo.winhighlight == ""
						and vim.bo.filetype ~= ""
				end

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
			-- Save file when leaving insert mode
			event = { "InsertLeave", "BufLeave" },
			pattern = { "*" },
			command = function()
				local save_excluded = {}

				local function can_save()
					return helper.empty(vim.bo.buftype)
						and not helper.empty(vim.bo.filetype)
						and vim.bo.modifiable
						and not vim.tbl_contains(save_excluded, vim.bo.filetype)
				end

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
				vim.wo.numberwidth = 3 -- Set minimum number column width
				vim.wo.signcolumn = "yes:1" -- Always show sign column to prevent reflo
				-- Combine line number and sign column visually
				vim.opt.statuscolumn = "%l%s"
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
				-- We don't explicitly set numberwidth or signcolumn to defaults on leave,
				-- as WinEnter/BufEnter will set them correctly when re-entering.
				-- This also allows other autocmds (like for terminals) to override.
			end,
		},
	},

	-- For general other stuff
	-- AruVimAuRc = {
	-- 	{
	-- 		event = { "TextYankPost" },
	-- 		pattern = { "*" },
	-- 		command = function()
	-- 			vim.hl.on_yank({
	-- 				on_visual = false,
	-- 				higroup = "IncSearch",
	-- 				timeout = 100,
	-- 			})
	-- 		end,
	-- 	},
	-- },
}

-----------------------------------------------------------------------------//
-- Utils
-----------------------------------------------------------------------------//

log:debug("Setting up custom augroups")

for grp, cmds in pairs(augroups) do
	log:debug(fmt("Creating commands for group %s", grp))

	helper.create_augroup(grp, cmds)
end

return {}
