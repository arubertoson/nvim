---@module "aru.workspace.sessions"
---One-file workspace resume. Tracks owns live visits; this config owns their storage.

local log = require("aru.log")
local scope = require("tracks.scope")
local file_jump = require("tracks.file_jump")
local file_config = require("tracks.config").defaults.file_jump

-- Resume only file visits, not ShaDa registers, command history, or old files.
vim.opt.shada = ""

local M = {}
local storage_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "aru-resume")
local workspace = scope.for_source(vim.uv.cwd()).root

local function storage_path(root)
    return vim.fs.joinpath(storage_dir, vim.fn.sha256(root) .. ".json")
end

local function relative_file(root, path)
    local rel = vim.fs.relpath(root, path)
    if not rel or rel == ".." or vim.startswith(rel, "../") or rel == "." then return nil end
    return rel
end

local function empty_trail() return { entries = {}, index = 0, alternate_index = nil } end

-- Workspace files use relative paths; files outside the workspace retain their
-- absolute paths. Missing files are discarded without creating buffers.
local function read_trail(root)
    local path = storage_path(root)
    if vim.fn.filereadable(path) == 0 then return empty_trail(), nil end

    local ok, data = pcall(
        function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end
    )
    if
        not ok
        or type(data) ~= "table"
        or data.version ~= 1
        or data.root ~= root
        or type(data.trail) ~= "table"
        or type(data.trail.entries) ~= "table"
        or not vim.islist(data.trail.entries)
        or #data.trail.entries > file_config.max_history
    then
        log.warn("Ignoring invalid workspace resume", path)
        return empty_trail(), nil
    end

    local source = data.trail
    local entries, indices = {}, {}
    for i, entry in ipairs(source.entries) do
        if type(entry) ~= "table" or type(entry.path) ~= "string" then
            log.warn("Ignoring invalid workspace resume", path)
            return empty_trail(), nil
        end
        local external = vim.startswith(entry.path, "/")
        local absolute = external and entry.path or vim.fs.joinpath(root, entry.path)
        if
            vim.fs.normalize(absolute) ~= absolute
            or (not external and relative_file(root, absolute) ~= entry.path)
        then
            log.warn("Ignoring invalid workspace resume path", path)
            return empty_trail(), nil
        end
        local stat = vim.uv.fs_stat(absolute)
        if stat and stat.type == "file" then
            entries[#entries + 1] = { path = absolute, view = entry.view }
            indices[i] = #entries
        end
    end

    local index = source.index
    local alternate = source.alternate_index
    if type(index) ~= "number" or index % 1 ~= 0 or index < 0 or index > #source.entries then
        log.warn("Ignoring invalid workspace resume index", path)
        return empty_trail(), nil
    end
    if
        alternate ~= nil
        and (
            type(alternate) ~= "number"
            or alternate % 1 ~= 0
            or alternate < 1
            or alternate > #source.entries
        )
    then
        log.warn("Ignoring invalid workspace resume alternate", path)
        return empty_trail(), nil
    end

    local selected = indices[index]
    local new_index = selected
    if not new_index and #entries > 0 then
        for i = index, 1, -1 do
            if indices[i] then
                new_index = indices[i]
                break
            end
        end
        new_index = new_index or 1
    end
    return {
        entries = entries,
        index = new_index or 0,
        alternate_index = indices[alternate],
    },
        selected and entries[selected] or nil
end

local function save_trail(root)
    local snapshot = file_jump.snapshot()
    local entries, indices = {}, {}
    for i, entry in ipairs(snapshot.entries) do
        local stat = vim.uv.fs_stat(entry.path)
        if stat and stat.type == "file" then
            entries[#entries + 1] = {
                path = relative_file(root, entry.path) or entry.path,
                view = entry.view,
            }
            indices[i] = #entries
        end
    end
    if #entries == 0 then return end

    local index = indices[snapshot.index]
    if not index then
        for i = snapshot.index, 1, -1 do
            if indices[i] then
                index = indices[i]
                break
            end
        end
        index = index or 1
    end
    local data = {
        version = 1,
        root = root,
        trail = {
            entries = entries,
            index = index,
            alternate_index = indices[snapshot.alternate_index],
        },
    }

    vim.fn.mkdir(storage_dir, "p")
    local destination = storage_path(root)
    local temporary = ("%s.tmp.%d.%s"):format(destination, vim.uv.os_getpid(), vim.uv.hrtime())
    local ok, result = pcall(vim.fn.writefile, { vim.json.encode(data) }, temporary)
    if not ok or result ~= 0 then
        vim.uv.fs_unlink(temporary)
        log.warn("Cannot write workspace resume", destination, result)
        return
    end
    local renamed, err = vim.uv.fs_rename(temporary, destination)
    if not renamed then
        vim.uv.fs_unlink(temporary)
        log.warn("Cannot replace workspace resume", destination, err)
    end
end

local function import_trail(root, record_current)
    local trail, selected = read_trail(root)
    local ok, err = pcall(file_jump.import, trail, { record_current = record_current })
    if not ok then
        log.warn("Ignoring invalid workspace resume trail", storage_path(root), err)
        file_jump.import(empty_trail(), { record_current = record_current })
        return nil
    end
    return selected
end

-- During init.lua, Neovim has already assigned the initial argument's buffer
-- name. A directory argument is a workspace request, not an explicit file.
local explicit_file = vim.fn.argc() > 0
    and not (vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1)

local selected = import_trail(workspace, explicit_file)
file_jump._setup(file_config)
if not explicit_file and selected then
    vim.cmd.edit({ args = { selected.path } })
    local lines = math.max(1, vim.api.nvim_buf_line_count(0))
    local view = vim.deepcopy(selected.view)
    view.lnum = math.max(1, math.min(view.lnum, lines))
    view.topline = math.max(1, math.min(view.topline, lines))
    vim.fn.winrestview(view)
end

local group = vim.api.nvim_create_augroup("aru_workspace_resume", { clear = true })
vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    desc = "Switch workspace file visits with cwd",
    callback = function()
        local root = scope.for_source(vim.uv.cwd()).root
        if root == workspace then return end
        save_trail(workspace)
        workspace = root
        import_trail(root, false)
    end,
})
vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "Save current workspace file visits",
    callback = function() save_trail(workspace) end,
})

return M
