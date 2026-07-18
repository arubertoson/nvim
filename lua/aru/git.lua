---@module "aru.git"
---@brief Small synchronous git/path helpers.

local M = {}

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

return M
