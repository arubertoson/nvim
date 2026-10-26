---@module "aru.workspace.hunk_preview"
---One inline snapshot, dismissed on edits, reloads, or leaving its window.
---VCSigns supplies the baseline and word diff data when Space opens a hunk.
---Repository refreshes do not change an open snapshot. Each observed buffer
---owns one change subscription until it is detached.

local diff = require("vcsigns.diff")
local hunkops = require("vcsigns.hunkops")
local vc_state = require("vcsigns.state")

local M = {}
local ns = vim.api.nvim_create_namespace("aru_hunk_preview")

---@class AruHunkPreview
---@field buf integer
---@field first integer
---@field last integer

---@type AruHunkPreview?
local active
local watched = {}

function M.close()
    local preview = active
    if not preview then return end
    active = nil
    if vim.api.nvim_buf_is_valid(preview.buf) then
        vim.api.nvim_buf_clear_namespace(preview.buf, ns, 0, -1)
    end
end

local function watch_buffer(buf)
    if watched[buf] then return end

    local function invalidate()
        if active and active.buf == buf then M.close() end
    end

    -- Line updates are synchronous. Delayed TextChanged events and save-only
    -- changedtick updates must not dismiss a snapshot opened after an edit.
    local attached = vim.api.nvim_buf_attach(buf, false, {
        on_lines = invalidate,
        on_reload = invalidate,
        on_detach = function()
            watched[buf] = nil
            invalidate()
        end,
    })
    if not attached then error("Cannot observe hunk preview buffer " .. buf) end
    watched[buf] = true
end

local function render(buf, hunk)
    local word_diff = diff.intra_diff(hunk)
    local deleted = {}
    for row, text in ipairs(hunk.minus_lines) do
        local chunks = {}
        local column = 0
        for _, interval in ipairs(word_diff.minus_intervals[row] or {}) do
            if column < interval[1] then
                chunks[#chunks + 1] = { text:sub(column + 1, interval[1]), "VcsignsDiffDelete" }
            end
            chunks[#chunks + 1] = {
                text:sub(interval[1] + 1, interval[2]),
                "VcsignsDiffTextDelete",
            }
            column = interval[2]
        end
        chunks[#chunks + 1] = { text:sub(column + 1), "VcsignsDiffDelete" }
        deleted[#deleted + 1] = chunks
    end

    local first_row = hunkops.hunk_visual_start(hunk) - 1
    if #deleted > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns, first_row + hunkops.hunk_visual_size(hunk) - 1, 0, {
            virt_lines = deleted,
            virt_lines_above = hunk.plus_start == 0 and hunk.plus_count == 0,
            virt_lines_overflow = "scroll",
        })
    end

    for offset = 0, hunk.plus_count - 1 do
        vim.api.nvim_buf_set_extmark(buf, ns, first_row + offset, 0, {
            line_hl_group = "VcsignsDiffAdd",
            priority = 3,
        })
    end
    for offset, intervals in pairs(word_diff.plus_intervals) do
        for _, interval in ipairs(intervals) do
            vim.api.nvim_buf_set_extmark(buf, ns, first_row + offset - 1, interval[1], {
                end_col = interval[2],
                hl_group = "VcsignsDiffTextAdd",
            })
        end
    end
end

function M.toggle()
    local buf = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local previous = active
    M.close()
    if previous and previous.buf == buf and line >= previous.first and line <= previous.last then
        return
    end

    local state = vc_state.get(buf)
    if not state.vcs.vcs or state.diff.last_update == 0 then return end

    -- Text edits can precede VCSigns' next sign refresh, so use its baseline
    -- with the current buffer text rather than its cached hunks.
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local hunk = hunkops.cur_hunk(line, diff.compute_diff(state.diff.old_lines, lines))
    if not hunk then return end

    watch_buffer(buf)
    local first = hunkops.hunk_visual_start(hunk)
    active = { buf = buf, first = first, last = first + hunkops.hunk_visual_size(hunk) - 1 }
    render(buf, hunk)
end

return M
