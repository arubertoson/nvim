---@module "aru.agent.ui"
---Small Neovim UI helpers shared by agent floating windows.

local M = {}

local markview_autocmds_ready = false

---@return table|nil
local function markview_actions()
    if not markview_autocmds_ready then
        local ok, autocmds = pcall(require, "markview.autocmds")
        if not ok then return nil end
        local setup_ok = pcall(autocmds.setup)
        if not setup_ok then return nil end
        markview_autocmds_ready = true
    end

    local ok, actions = pcall(require, "markview.actions")
    if not ok then return nil end
    return actions
end

---@class AgentScratchBufOpts
---@field filetype string|nil
---@field lines string[]|nil
---@field modifiable boolean|nil

---Creates a scratch nofile buffer with common agent defaults.
---@param opts AgentScratchBufOpts|nil
---@return integer
function M.create_scratch_buf(opts)
    opts = opts or {}
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    if opts.filetype then
        vim.api.nvim_set_option_value("filetype", opts.filetype, { buf = buf })
    end
    if opts.lines then vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines) end
    if opts.modifiable ~= nil then
        vim.api.nvim_set_option_value("modifiable", opts.modifiable, { buf = buf })
    end
    return buf
end

---Applies window-local options from a key-value table.
---@param win integer
---@param opts table<string, any>
---@return nil
function M.apply_win_options(win, opts)
    for name, value in pairs(opts) do
        vim.api.nvim_set_option_value(name, value, { win = win })
    end
end

---Closes a floating window and deletes its backing buffer when still valid.
---@param win integer
---@param buf integer
---@return nil
function M.close_win_buf(win, buf)
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
end

---Attaches Markview to a scratch markdown buffer.
---
---Markview's filetype autocmds skip `nofile` buffers by default, so agent
---markdown floats need to opt in explicitly.
---@param buf integer
---@return nil
function M.attach_markview(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local actions = markview_actions()
    if not actions then return end
    pcall(actions.attach, buf, { enable = true, hybrid_mode = false })
end

---Refreshes Markview rendering for a scratch markdown buffer.
---
---Agent read floats are updated with API buffer writes, which do not reliably
---drive Markview's normal TextChanged path.
---@param buf integer
---@return nil
function M.render_markview(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local actions = markview_actions()
    if not actions then return end
    pcall(actions.render, buf, { enable = true, hybrid_mode = false })
end

return M
