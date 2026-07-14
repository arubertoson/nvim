---@module "aru.state.git"
---
--- Git state tracking, I know there are tools out there for things like this, but

local git = require("aru.git")
local log = require("aru.log")
local M = {}
local state = {}

---@param entry table
local function ensure_watcher(entry)
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

local function entry_for(root)
    local head = git.head_path(root)
    local entry = state[root]
    if not entry then
        entry = { head = head, head_exists = head and vim.uv.fs_stat(head) ~= nil or false }
        state[root] = entry
    else
        entry.head = head
        entry.head_exists = head and vim.uv.fs_stat(head) ~= nil or false
    end
    return entry
end

---Refresh the branch cache asynchronously.
---@param root string
---@param cb fun(branch: string?)|nil
function M.refresh(root, cb)
    local entry = entry_for(root)
    if not entry.head_exists then
        entry.branch = nil
        if cb then cb(nil) end
        return
    end

    ensure_watcher(entry)
    if entry.pending then
        if cb then
            entry.callbacks = entry.callbacks or {}
            table.insert(entry.callbacks, cb)
        end
        return
    end
    entry.pending = true
    entry.callbacks = cb and { cb } or {}

    vim.system(
        { "git", "symbolic-ref", "--short", "HEAD" },
        { cwd = root, text = true },
        function(result)
            local branch = nil
            if result.code == 0 then branch = vim.trim(result.stdout) end

            vim.schedule(function()
                entry.pending = false
                entry.branch = branch
                local callbacks = entry.callbacks or {}
                entry.callbacks = nil
                for _, callback in ipairs(callbacks) do
                    callback(branch)
                end
            end)
        end
    )
end

---Determine the current branch for a given root from cache only.
---If no value has been cached yet, an asynchronous refresh is started.
---@param root string
---@return string?
function M.branch_for(root)
    local entry = state[root]
    if entry and entry.branch ~= nil then return entry.branch end

    M.refresh(root)
    return entry and entry.branch or nil
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
                entry.watcher = nil
            end
        end
    end,
})

M._test = {
    state = state,
    reset = function()
        for _, entry in pairs(state) do
            if entry.watcher then
                pcall(function() entry.watcher:stop() end)
                pcall(function() entry.watcher:close() end)
            end
        end
        for k in pairs(state) do
            state[k] = nil
        end
    end,
    ensure_watcher = ensure_watcher,
}

return M
