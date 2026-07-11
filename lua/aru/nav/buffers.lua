---@module "aru.nav.buffers"
---@brief MRU loaded-buffer cache.
---
--- Active files are pinned elsewhere. This module keeps a small number of
--- recently-used normal file buffers warm so cross-file navigation does not
--- constantly reload large files.

local log = require("aru.log")

local M = {}

---@class AruNavBuffers.Config
---@field max_buffers number Total normal file buffers to keep loaded.
---@field is_pinned fun(path: string): boolean
---@field augroup_id number?
local default_config = {
    max_buffers = 8,
    is_pinned = function() return false end,
    augroup_id = nil,
}

---@type AruNavBuffers.Config
M.config = vim.tbl_extend("force", {}, default_config)

---@type string[] Most recent first.
M._mru = {}

local function normalize(path)
    if not path or path == "" then return nil end
    return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

---@param bufnr number
---@return string?
local function buffer_path(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return nil end
    return normalize(vim.api.nvim_buf_get_name(bufnr))
end

---@param bufnr number
---@return boolean
local function is_normal_file_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return false
    end

    if not buffer_path(bufnr) then return false end

    local bt = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
    if bt ~= "" then return false end

    return true
end

---@param bufnr number
---@return boolean
local function is_visible(bufnr)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then return true end
    end
    return false
end

---@param bufnr number
---@return boolean
local function is_protected(bufnr)
    if not is_normal_file_buffer(bufnr) then return true end
    if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then return true end
    if is_visible(bufnr) then return true end

    local path = buffer_path(bufnr)
    if path and M.config.is_pinned(path) then return true end

    local ok, protected = pcall(vim.api.nvim_buf_get_var, bufnr, "__bufdel_protected")
    if ok and protected then return true end

    return false
end

---@param path string
local function remove_from_mru(path)
    for i = #M._mru, 1, -1 do
        if M._mru[i] == path then table.remove(M._mru, i) end
    end
end

---@param path string
local function promote(path)
    remove_from_mru(path)
    table.insert(M._mru, 1, path)
end

local function mru_rank(path)
    for i, candidate in ipairs(M._mru) do
        if candidate == path then return i end
    end

    return math.huge
end

local function loaded_file_buffers()
    local buffers = {}

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if is_normal_file_buffer(bufnr) then
            local path = buffer_path(bufnr)
            if path then
                buffers[#buffers + 1] = {
                    bufnr = bufnr,
                    path = path,
                    rank = mru_rank(path),
                }
            end
        end
    end

    table.sort(buffers, function(a, b) return a.rank < b.rank end)

    return buffers
end

---@param bufnr number?
function M.touch(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not is_normal_file_buffer(bufnr) then return end

    local path = buffer_path(bufnr)
    if not path then return end

    promote(path)
end

function M.prune()
    local buffers = loaded_file_buffers()
    local loaded_count = #buffers
    if loaded_count <= M.config.max_buffers then return end

    -- Delete coldest buffers first. `buffers` is most-recent-first, so walk it
    -- backwards. Stop when the total normal-file buffer count is back under max.
    for i = #buffers, 1, -1 do
        if loaded_count <= M.config.max_buffers then return end

        local entry = buffers[i]
        if not is_protected(entry.bufnr) then
            local ok, err = pcall(vim.api.nvim_buf_delete, entry.bufnr, { force = false })
            if ok then
                loaded_count = loaded_count - 1
                remove_from_mru(entry.path)
                log:debug("buffers: pruned %s", entry.path)
            else
                log:debug("buffers: failed to prune %s: %s", entry.path, err)
            end
        end
    end
end

---@return string[] Most recent first.
function M.tracked()
    local paths = {}
    for i, path in ipairs(M._mru) do
        paths[i] = path
    end
    return paths
end

---@param opts AruNavBuffers.Config?
function M.setup(opts)
    M.config = vim.tbl_extend("force", M.config, opts or {})

    M.touch(0)
    vim.schedule(M.prune)

    if not M.config.augroup_id then
        M.config.augroup_id = vim.api.nvim_create_augroup("aru_nav_buffers", { clear = true })

        vim.api.nvim_create_autocmd("BufEnter", {
            group = M.config.augroup_id,
            desc = "Aru buffers: promote current file buffer",
            callback = function(ev)
                M.touch(ev.buf)
                vim.schedule(M.prune)
            end,
        })

        vim.api.nvim_create_autocmd({ "BufHidden", "BufDelete", "BufWipeout" }, {
            group = M.config.augroup_id,
            desc = "Aru buffers: prune cold file buffers",
            callback = function(ev)
                local path = buffer_path(ev.buf)
                if path and (ev.event == "BufDelete" or ev.event == "BufWipeout") then
                    remove_from_mru(path)
                end

                vim.schedule(M.prune)
            end,
        })
    end
end

return M
