---@module "aru.agent.context"
---Collects Neovim editor context for agent requests. This module snapshots the
---current visual selection when available, otherwise it falls back to a bounded
---range around the cursor.

local M = {}

local constants = require("aru.agent.constants")

---Describes one item of editor context sent to the agent.
---
---Paths are included only for file-backed context. Line numbers are 1-indexed
---and inclusive when present. `text` is the exact body rendered into the agent
---payload.
---@class AgentContextItem
---@field kind "selection"|"file"|"path"
---@field path string|nil
---@field filetype string|nil
---@field start_line integer|nil
---@field end_line integer|nil
---@field text string

---Collects a range of lines around the current cursor.
---
---`n_lines` is applied symmetrically above and below the cursor, then clamped to
---the current buffer bounds. Returns nil when there is no text to include.
---@param n_lines integer
---@return AgentContextItem|nil
local function collect_surrounding(n_lines)
    local buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo[buf].filetype or ""
    local path = vim.api.nvim_buf_get_name(buf)

    local total = vim.api.nvim_buf_line_count(buf)
    if total == 0 then return nil end

    local row = vim.api.nvim_win_get_cursor(0)[1]
    local start_line = math.max(1, row - n_lines)
    local end_line = math.min(total, row + n_lines)

    local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    if vim.tbl_isempty(lines) then return nil end

    local text = table.concat(lines, "\n")
    if text == "" then return nil end

    return {
        kind = "file",
        path = path ~= "" and path or nil,
        filetype = ft,
        start_line = start_line,
        end_line = end_line,
        text = text,
    }
end

---Collects the active visual selection from the current buffer.
---
---Line-wise selections keep full lines. Character-wise selections are trimmed
---using Vim's visual marks, which are byte-column based.
---@param visual_mode string
---@return AgentContextItem|nil
local function collect_visual_selection(visual_mode)
    local buf = vim.api.nvim_get_current_buf()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    local start_line = start_pos[2]
    local end_line = end_pos[2]

    if start_line == 0 or end_line == 0 or start_line > end_line then return nil end

    local start_col = start_pos[3]
    local end_col = end_pos[3]
    if start_line == end_line and end_col < start_col then return nil end

    local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    if vim.tbl_isempty(lines) then return nil end

    -- Visual marks are byte-column based, so line slices intentionally mirror Vim's selection marks.
    if visual_mode ~= "V" then
        lines[#lines] = lines[#lines]:sub(1, end_col)
        lines[1] = lines[1]:sub(start_col)
    end

    local ft = vim.bo[buf].filetype or ""
    local path = vim.api.nvim_buf_get_name(buf)

    return {
        kind = "selection",
        path = path ~= "" and path or nil,
        filetype = ft,
        start_line = start_line,
        end_line = end_line,
        text = table.concat(lines, "\n"),
    }
end

---Snapshots context at call time, preferring visual selection over surrounding lines.
---
---When there is no active visual selection, surrounding context is collected from
---the cursor using the default surrounding line count unless overridden.
---@param surrounding_lines integer|nil
---@return AgentContextItem[]
---Example:
---```lua
---local items = require("aru.agent.context").collect(25)
---```
function M.collect(surrounding_lines)
    surrounding_lines = surrounding_lines or constants.DEFAULT_SURROUNDING_LINES

    local mode = vim.api.nvim_get_mode().mode
    local has_visual = mode == "v"
        or mode == "V"
        or mode == "\22"
        or mode == "s"
        or mode == "S"
        or mode == "\19"

    if has_visual then
        local item = collect_visual_selection(mode)
        if item then return { item } end
    end

    local item = collect_surrounding(surrounding_lines)
    if item then return { item } end

    return {}
end

return M
