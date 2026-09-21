---@module "aru.git"
---@brief Small synchronous git/path helpers.

local log = require("aru.log")

local M = {}
local branch_state = {}

local function normalize(path)
    if not path or path == "" then return nil end
    return vim.fs.normalize(vim.fs.abspath(path))
end

---@param source string|number|nil Path, buffer number, or current buffer when nil.
---@return string?
local function path_from_source(source)
    if type(source) == "number" then
        if not vim.api.nvim_buf_is_valid(source) then return nil end
        return normalize(vim.api.nvim_buf_get_name(source))
    end

    if type(source) == "string" then return normalize(source) end

    return normalize(vim.api.nvim_buf_get_name(0))
end

---@param source string|number|nil Path, buffer number, or current buffer when nil.
---@return string?
function M.git_root(source)
    local path = path_from_source(source)
    if not path then return nil end

    local root = vim.fs.root(path, { ".git" })
    return root and normalize(root) or nil
end

---@param source string|number|nil Path, buffer number, or current buffer when nil.
---@return string?
function M.project_root(source)
    local path = path_from_source(source)
    if not path then return nil end

    return M.git_root(path) or normalize(vim.uv.cwd() or vim.fs.dirname(path) or path) or ""
end

---@param root string
---@return string?
function M.git_dir(root)
    local git = vim.fs.joinpath(root, ".git")
    local stat = vim.uv.fs_stat(git)
    if not stat then return nil end
    if stat.type == "directory" then return git end

    -- Worktrees store .git as a file pointing at the real git dir.
    if stat.type == "file" then
        local ok, lines = pcall(vim.fn.readfile, git, "", 1)
        local gitdir = ok and lines[1] and lines[1]:match("gitdir:%s*(.+)")
        if gitdir then
            if not vim.startswith(gitdir, "/") then gitdir = vim.fs.joinpath(root, gitdir) end
            return normalize(gitdir)
        end
    end

    return nil
end

---@param root string
---@return string?
function M.head_path(root)
    local gitdir = M.git_dir(root)
    return gitdir and vim.fs.joinpath(gitdir, "HEAD") or nil
end

---@param root string
---@return string branch Current branch, detached HEAD short hash, or "-".
function M.branch_sync(root)
    local head_path = M.head_path(root)
    if not head_path then return "-" end

    local ok, lines = pcall(vim.fn.readfile, head_path, "", 1)
    local head = ok and lines[1] or nil
    if not head or head == "" then return "-" end

    return head:match("^ref:%s*refs/heads/(.+)$") or head:sub(1, 12)
end

---@class AruGit.Scope
---@field root string
---@field branch string

---@param source string|number|nil Path, buffer number, or current buffer when nil.
---@return AruGit.Scope?
function M.scope_for(source)
    local root = M.project_root(source)
    if not root then return nil end

    return {
        root = root,
        branch = M.branch_sync(root),
    }
end

---@class AruGit.BranchEntry
---@field head string?
---@field head_exists boolean
---@field branch string?
---@field pending boolean?
---@field callbacks fun(branch: string?)[]?
---@field watcher uv.uv_fs_event_t?

---@param root string
---@return AruGit.BranchEntry
local function branch_entry(root)
    local head = M.head_path(root)
    local entry = branch_state[root]
    if not entry then
        entry = {}
        branch_state[root] = entry
    end

    entry.head = head
    entry.head_exists = head ~= nil and vim.uv.fs_stat(head) ~= nil
    return entry
end

---@param root string
---@param branch string?
local function emit_branch_changed(root, branch)
    vim.api.nvim_exec_autocmds("User", {
        pattern = "AruGitBranchChanged",
        modeline = false,
        data = { root = root, branch = branch },
    })
end

---@param root string
---@param entry AruGit.BranchEntry
local function ensure_branch_watcher(root, entry)
    if entry.watcher or not entry.head_exists then return end

    local handle, err = vim.uv.new_fs_event()
    if not handle then error(("failed to create Git HEAD watcher: %s"):format(err)) end

    local ok, start_err = handle:start(entry.head, {}, function(watch_err)
        if watch_err then
            log.error("Git HEAD watcher failed", watch_err)
            return
        end

        entry.branch = nil
        vim.schedule(function() M.refresh_branch(root) end)
    end)
    if not ok then
        handle:close()
        error(("failed to watch Git HEAD: %s"):format(start_err))
    end

    entry.watcher = handle
end

---Refresh the cached branch asynchronously.
---@param root string
---@param callback? fun(branch: string?)
function M.refresh_branch(root, callback)
    local entry = branch_entry(root)
    if not entry.head_exists then
        entry.branch = nil
        if callback then callback(nil) end
        emit_branch_changed(root, nil)
        return
    end

    ensure_branch_watcher(root, entry)
    if entry.pending then
        if callback then
            entry.callbacks = entry.callbacks or {}
            entry.callbacks[#entry.callbacks + 1] = callback
        end
        return
    end

    entry.pending = true
    entry.callbacks = callback and { callback } or {}

    vim.system(
        { "git", "symbolic-ref", "--short", "HEAD" },
        { cwd = root, text = true },
        function(result)
            local branch = result.code == 0 and vim.trim(result.stdout) or nil
            vim.schedule(function()
                entry.pending = false
                entry.branch = branch

                local callbacks = entry.callbacks or {}
                entry.callbacks = nil
                for _, pending_callback in ipairs(callbacks) do
                    pending_callback(branch)
                end

                emit_branch_changed(root, branch)
            end)
        end
    )
end

---Return the cached branch, starting an asynchronous refresh when absent.
---@param root string
---@return string?
function M.branch_for(root)
    local entry = branch_state[root]
    if entry and entry.branch ~= nil then return entry.branch end

    M.refresh_branch(root)
    return entry and entry.branch or nil
end

local function close_branch_watchers()
    for _, entry in pairs(branch_state) do
        if entry.watcher then
            entry.watcher:stop()
            entry.watcher:close()
            entry.watcher = nil
        end
    end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("aru_git_state", { clear = true }),
    desc = "Release Git HEAD watchers",
    callback = close_branch_watchers,
})

if vim.g.aru_test then
    M._test = {
        branch_state = branch_state,
        reset = function()
            close_branch_watchers()
            for root in pairs(branch_state) do
                branch_state[root] = nil
            end
        end,
    }
end

return M
