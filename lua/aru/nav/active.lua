---@module "aru.nav.active"
---@brief Small persisted working set of active files.

local log = require("aru.log")

local M = {}

---@class AruNavActive.Config
---@field max_files number
---@field storage_path string
---@field before_select fun()? Called before switching to an active file.
---@field augroup_id number?
local default_config = {
    max_files = 3,
    storage_path = vim.fs.joinpath(vim.fn.stdpath("state"), "aru-active.json"),
    before_select = nil,
    augroup_id = nil,
}

---@class AruNavActive.Item
---@field path string Absolute normalized path.
---@field bufnr number?

---@class AruNavActive.Scope
---@field root string
---@field branch string
---@field key string

---@type AruNavActive.Config
M.config = vim.tbl_extend("force", {}, default_config)

---@type AruNavActive.Item[]
M._items = {}

---@type table<string, { root: string, branch: string, items: string[] }>
M._store = {}

M._store_loaded = false

---@type AruNavActive.Scope?
M._scope = nil

local function normalize(path)
    if not path or path == "" then return nil end
    return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

---@param bufnr number
---@return boolean
local function is_normal_file_buffer(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return false end

    local path = normalize(vim.api.nvim_buf_get_name(bufnr))
    if not path then return false end

    local bt = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
    if bt ~= "" then return false end

    return true
end

---@param path string
---@return string?
local function find_git_root(path)
    local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
    if not dir then return nil end

    if vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) then return dir end

    for parent in vim.fs.parents(dir) do
        if vim.uv.fs_stat(vim.fs.joinpath(parent, ".git")) then return parent end
    end

    return nil
end

---@param path string
---@return string
local function find_root(path)
    local root = find_git_root(path)
    if root then return normalize(root) or root end

    local cwd = vim.uv.cwd()
    return normalize(cwd or vim.fs.dirname(path) or path) or ""
end

---@param root string
---@return string
local function read_branch(root)
    local git = vim.fs.joinpath(root, ".git")
    local head_path = vim.fs.joinpath(git, "HEAD")

    -- Worktrees store .git as a file pointing at the real git dir.
    local stat = vim.uv.fs_stat(git)
    if stat and stat.type == "file" then
        local ok, lines = pcall(vim.fn.readfile, git, "", 1)
        local gitdir = ok and lines[1] and lines[1]:match("gitdir:%s*(.+)")
        if gitdir then
            if not vim.startswith(gitdir, "/") then gitdir = vim.fs.joinpath(root, gitdir) end
            head_path = vim.fs.joinpath(gitdir, "HEAD")
        end
    end

    local ok, lines = pcall(vim.fn.readfile, head_path, "", 1)
    if not ok then return "-" end

    local head = lines[1]
    if not head or head == "" then return "-" end

    local branch = head:match("^ref:%s*refs/heads/(.+)$")
    if branch and branch ~= "" then return branch end

    -- Detached HEAD: keep a stable short identifier without claiming a branch.
    return head:sub(1, 12)
end

---@param root string
---@param branch string
---@return string
local function scope_key(root, branch) return root .. "\t" .. branch end

---@param path string?
---@return AruNavActive.Scope?
local function scope_for(path)
    path = normalize(path or vim.api.nvim_buf_get_name(0))
    if not path then return nil end

    local root = find_root(path)
    local branch = read_branch(root)

    return {
        root = root,
        branch = branch,
        key = scope_key(root, branch),
    }
end

local function read_store()
    local path = M.config.storage_path
    if vim.fn.filereadable(path) ~= 1 then
        M._store = {}
        M._store_loaded = true
        return
    end

    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    if ok and type(decoded) == "table" then
        M._store = decoded
    else
        log:warn("active: failed to read %s", path)
        M._store = {}
    end

    M._store_loaded = true
end

local function ensure_store_loaded()
    if not M._store_loaded then read_store() end
end

local function write_store()
    vim.fn.mkdir(vim.fs.dirname(M.config.storage_path), "p")

    local ok, encoded = pcall(vim.json.encode, M._store)
    if not ok then
        log:warn("active: failed to encode store: %s", encoded)
        return
    end

    vim.fn.writefile(vim.split(encoded, "\n", { plain = true }), M.config.storage_path)
end

local function emit_updated()
    vim.api.nvim_exec_autocmds("User", {
        pattern = "AruActiveUpdated",
        modeline = false,
        data = {
            scope = M._scope,
            items = M.items(),
        },
    })
end

---@param scope AruNavActive.Scope
local function load_scope(scope)
    M._scope = scope
    M._items = {}

    local entry = M._store[scope.key]
    if not entry or type(entry.items) ~= "table" then
        emit_updated()
        return
    end

    for _, rel in ipairs(entry.items) do
        if #M._items >= M.config.max_files then break end

        local path = normalize(vim.fs.joinpath(scope.root, rel))
        if path then
            local bufnr = vim.fn.bufnr(path)
            M._items[#M._items + 1] = { path = path, bufnr = bufnr ~= -1 and bufnr or nil }
        end
    end

    emit_updated()
end

local function save_scope()
    local scope = M._scope or scope_for()
    if not scope then return end
    M._scope = scope

    local rels = {}
    for _, item in ipairs(M._items) do
        local rel = vim.fs.relpath(scope.root, item.path)
        rels[#rels + 1] = rel or item.path
    end

    M._store[scope.key] = {
        root = scope.root,
        branch = scope.branch,
        items = rels,
    }

    write_store()
end

local function refresh_scope()
    ensure_store_loaded()

    local scope = scope_for()
    if not scope then return end
    if M._scope and M._scope.key == scope.key then return end

    load_scope(scope)
end

---@param target number|string|nil
---@return string?
local function path_from_target(target)
    if type(target) == "number" then
        if target >= 1 and target <= M.config.max_files and M._items[target] then
            return M._items[target].path
        end

        if vim.api.nvim_buf_is_valid(target) then return normalize(vim.api.nvim_buf_get_name(target)) end
        return nil
    end

    if type(target) == "string" then return normalize(target) end

    return normalize(vim.api.nvim_buf_get_name(0))
end

---@param path string
---@return number?
local function loaded_bufnr_for_path(path)
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then return bufnr end
    return nil
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
local function is_delete_protected(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return true end
    if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then return true end
    if is_visible(bufnr) then return true end

    local ok, protected = pcall(vim.api.nvim_buf_get_var, bufnr, "__bufdel_protected")
    if ok and protected then return true end

    return false
end

---@param path string
local function delete_removed_buffer(path)
    local bufnr = loaded_bufnr_for_path(path)
    if not bufnr or is_delete_protected(bufnr) then return end

    local ok, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
    if not ok then log:debug("active: failed to delete removed buffer %s: %s", path, err) end
end

---@param path string
---@return number?
function M.index_of(path)
    path = path_from_target(path)
    if not path then return nil end

    for i, item in ipairs(M._items) do
        if item.path == path then return i end
    end

    return nil
end

---@param target number|string|nil
---@return boolean
function M.contains(target)
    local path = path_from_target(target)
    if not path then return false end

    return M.index_of(path) ~= nil
end

---@return AruNavActive.Item[]
function M.items()
    local items = {}
    for i, item in ipairs(M._items) do
        items[i] = vim.tbl_extend("force", {}, item)
    end
    return items
end

---@param bufnr number?
---@return boolean added
function M.add(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not is_normal_file_buffer(bufnr) then return false end

    refresh_scope()

    local path = normalize(vim.api.nvim_buf_get_name(bufnr))
    if not path then return false end

    if M.index_of(path) then return false end

    if #M._items >= M.config.max_files then
        vim.notify(
            ("Active files full (%d/%d)"):format(#M._items, M.config.max_files),
            vim.log.levels.INFO
        )
        return false
    end

    M._items[#M._items + 1] = { path = path, bufnr = bufnr }
    save_scope()
    emit_updated()

    return true
end

---@param target number|string|nil Slot, path, bufnr, or current buffer when nil.
---@return boolean removed
function M.remove(target)
    refresh_scope()

    local path = path_from_target(target)
    if not path then return false end

    local index = M.index_of(path)
    if not index then return false end

    local removed = table.remove(M._items, index)
    save_scope()
    emit_updated()

    if removed then delete_removed_buffer(removed.path) end

    return true
end

---@param slot number
---@return boolean selected
function M.select(slot)
    refresh_scope()

    local item = M._items[slot]
    if not item then return false end

    if M.config.before_select then M.config.before_select() end

    local bufnr = loaded_bufnr_for_path(item.path)
    if not bufnr then
        if not vim.uv.fs_stat(item.path) then
            vim.notify("Active file no longer exists: " .. item.path, vim.log.levels.WARN)
            table.remove(M._items, slot)
            save_scope()
            emit_updated()
            return false
        end

        bufnr = vim.fn.bufadd(item.path)
        vim.fn.bufload(bufnr)
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then return false end

    item.bufnr = bufnr
    vim.api.nvim_set_current_buf(bufnr)
    emit_updated()

    return true
end

function M.toggle_menu()
    refresh_scope()

    if #M._items == 0 then
        vim.notify("No active files", vim.log.levels.INFO)
        return
    end

    local choices = {}
    for i, item in ipairs(M._items) do
        choices[i] = {
            slot = i,
            path = item.path,
            label = ("%d: %s"):format(i, vim.fs.basename(item.path)),
        }
    end

    vim.ui.select(choices, {
        prompt = "Active files",
        format_item = function(item) return item.label end,
    }, function(choice)
        if choice then M.select(choice.slot) end
    end)
end

---@param opts AruNavActive.Config?
function M.setup(opts)
    if opts and opts.storage_path and opts.storage_path ~= M.config.storage_path then
        M._store_loaded = false
    end

    M.config = vim.tbl_extend("force", M.config, opts or {})

    ensure_store_loaded()
    refresh_scope()

    if not M.config.augroup_id then
        M.config.augroup_id = vim.api.nvim_create_augroup("aru_nav_active", { clear = true })

        vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
            group = M.config.augroup_id,
            desc = "Aru active files: refresh project/branch scope",
            callback = refresh_scope,
        })
    end
end

return M
