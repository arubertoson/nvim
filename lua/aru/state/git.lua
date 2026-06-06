---@module "aru.core.git"
---
--- Git state tracking, I know there are tools out there for things like this, but

local log = require("aru.log")
local M = {}
local state = {}

--- Find the workspace root for the current buffer, we
--- achieve this by first utilizing LSP to find its current
--- workspace root. If that fails, we fallback to looking
--- for a .git directory in the parent directories.
---@param bufnr integer
---@return string?
local function find_workspace_root(bufnr)
    local root, ws

    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if #clients > 0 then
        for _, client in ipairs(clients) do
            ws = client.workspace_folders
            if ws ~= nil then
                root = ws[1].name
                break
            end
        end
    end

    -- If root is nil at this point we fallback to check for a
    -- .git directory as a last ditch effort.
    if root == nil then
        local buf_name = vim.api.nvim_buf_get_name(bufnr)
        -- If the buffer name is empty, we use the current working
        -- directory.
        if buf_name == "" then
            buf_name = vim.uv.cwd() or ""
            if buf_name == "" then
                log:error("Unable to determine workspace root for empty buffer")
            end
        end

        -- We look for a .git directory in the parent directories
        local dir = vim.fs.dirname(buf_name)
        for parent in vim.fs.parents(dir) do
            if vim.fs.dir(vim.fs.joinpath(parent, ".git")) then
                root = parent
                break
            end
        end
    end

    return root
end

local function ensure_watcher(root)
    local entry = state[root]
    if entry.watcher or not entry.head_exists then return end

    local handle, err = vim.uv.new_fs_event()
    if not handle then
        log:error("fs_event failed: %s", err)
        return
    end

    local ok = handle:start(entry.head, {}, function(watch_err)
        if watch_err then
            log:error("fs_event failed: %s", watch_err)
            return
        end
        entry.branch = nil
        vim.schedule(function() vim.cmd.redrawstatus() end)
    end)

    if not ok then
        log:error("fs_event start failed")
        return
    end

    entry.watcher = handle
end

---Determine the current branch for a given root, and cache the result to
---avoid recompute.
---@param root string
---@return string?
function M.branch_for(root)
    if not root then return nil end

    local entry = state[root]
    if entry and entry.branch then return entry.branch end

    local branch = nil
    local head = vim.fs.joinpath(root, ".git", "HEAD")
    if vim.uv.fs_stat(head) then
        local result = vim.system(
            { "git", "symbolic-ref", "--short", "HEAD" },
            { cwd = root, text = true }
        ):wait()
        if result.code == 0 then branch = vim.trim(result.stdout) end
    end

    state[root] = state[root]
        or { head = head, head_exists = vim.uv.fs_stat(head) ~= nil }
    state[root].branch = branch
    ensure_watcher(root)

    return branch
end

---When we exit neovim, we have to stop the watchers that we spun up.
vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
        local log = require("aru.log")

        for _, entry in pairs(state) do
            log:debug("stopping watcher for %s", entry.head)
            if entry.watcher then
                entry.watcher:stop()
                entry.watcher:close()
            end
        end
    end,
})

return M
