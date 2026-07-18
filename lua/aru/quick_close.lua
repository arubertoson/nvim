---@module "aru.quick_close"
---Shared handling for temporary windows that should close on `q`.

local M = {}

M.filetypes = {
    "help",
    "git-status",
    "git-log",
    "gitcommit",
    "notify",
    "messages",
    "noice",
    "checkhealth",
    "dbui",
    "log",
    "qf",
    "lspinfo",
}

---@param buf integer|nil
---@return boolean
function M.is_quick_close_buffer(buf)
    buf = buf or vim.api.nvim_get_current_buf()

    if not vim.api.nvim_buf_is_valid(buf) then return false end
    if vim.b[buf].aru_quick_close == true then return true end

    local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })

    return vim.tbl_contains(M.filetypes, ft)
end

---@param win integer|nil
---@return boolean
local function can_close_window(win)
    win = win or vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(win) then return false end
    local cfg = vim.api.nvim_win_get_config(win)
    return cfg.relative ~= "" or vim.fn.winnr("$") > 1
end

---Closes the focused quick-close window, if focus is currently in one.
---Returns true when `q` was handled, even if the last normal window cannot close.
---@return boolean
function M.close_current()
    if not M.is_quick_close_buffer(0) then return false end
    if can_close_window(0) then pcall(vim.api.nvim_win_close, 0, true) end
    return true
end

---@param buf integer|nil
---@return nil
function M.map_buffer(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.b[buf].aru_quick_close = true
    vim.keymap.set("n", "q", M.close_current, {
        buffer = buf,
        nowait = true,
        silent = true,
        desc = "Close temporary window",
    })
end

return M
