---@module "aru.agent.ui"
---Scratch buffer and floating window helpers shared by prompt and float.

local M = {}

---@class aru.agent.ui.ScratchBufOpts
---@field filetype string|nil
---@field lines string[]|nil
---@field modifiable boolean|nil

---@param opts aru.agent.ui.ScratchBufOpts|nil
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

---@param win integer
---@param opts table<string, any>
function M.apply_win_options(win, opts)
    for name, value in pairs(opts) do
        vim.api.nvim_set_option_value(name, value, { win = win })
    end
end

---@param win integer
---@param buf integer
function M.close_win_buf(win, buf)
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
end

return M
