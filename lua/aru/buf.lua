---@module "aru.buf"
---@brief Shared Neovim buffer inspection and file-path classification.
---
--- This module describes buffers; feature modules still own their eligibility
--- policies. In particular, quick-close behavior is not universally equivalent
--- to a transient buffer.

local M = {}

local plugin_ui_filetypes = {
    fff_file_info = true,
    fff_input = true,
    fff_list = true,
    fff_preview = true,
    fzf = true,
    minifiles = true,
    ["minifiles-help"] = true,
    minimap = true,
    mininotify = true,
    ["mininotify-history"] = true,
    minipick = true,
    ministarter = true,
    minitest = true,
    ["no-neck-pain"] = true,
    oil = true,
    oil_progress = true,
}

---@param path string
---@return string?
function M.normalize_path(path)
    if path == "" then return nil end
    return vim.fs.normalize(vim.fs.abspath(path))
end

---@param bufnr number
---@return boolean
function M.is_valid(bufnr) return vim.api.nvim_buf_is_valid(bufnr) end

---@param bufnr number
---@return boolean
function M.is_loaded(bufnr) return M.is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) end

---@param name string
---@return boolean
function M.is_uri(name) return name:match("^%a[%w+.-]*://") ~= nil end

---@param bufnr number
---@return boolean
function M.is_plugin_ui(bufnr)
    if not M.is_valid(bufnr) then return false end
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    return plugin_ui_filetypes[filetype] == true
end

---Return an absolute path only when the buffer represents a normal editor file.
---Unlisted buffers are accepted because bufadd() creates valid file buffers that
---remain unlisted until another operation explicitly lists them.
---@param bufnr number
---@return string?
function M.normal_file_path(bufnr)
    if not M.is_valid(bufnr) then return nil end
    if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then return nil end
    if M.is_plugin_ui(bufnr) then return nil end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" or M.is_uri(name) then return nil end

    return M.normalize_path(name)
end

---@param bufnr number
---@return boolean
function M.is_normal_file(bufnr) return M.normal_file_path(bufnr) ~= nil end

return M
