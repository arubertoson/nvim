--- Find files changed in the current jj change or Git working tree.
local M = {}

local function changed_files(root, command, git_status, active)
    vim.system(
        command,
        { cwd = root, text = true },
        vim.schedule_wrap(function(result)
            if not active() then return end
            if result.code ~= 0 then
                vim.notify("Failed to list changed files: " .. result.stderr, vim.log.levels.ERROR)
                return
            end

            local items = {}
            local paths = vim.split(result.stdout, "\0", { plain = true, trimempty = true })
            local i = 1
            while i <= #paths do
                local path = paths[i]
                if git_status then
                    local status = path:sub(1, 2)
                    path = path:sub(4)
                    if status:find("[RC]") then i = i + 1 end -- -z puts the old path next.
                end

                if vim.uv.fs_stat(vim.fs.joinpath(root, path)) then
                    table.insert(items, { path = vim.fs.joinpath(root, path), text = path })
                end
                i = i + 1
            end

            if #items == 0 then
                vim.notify("No changed files", vim.log.levels.INFO)
                return
            end

            require("mini.pick").start({
                source = {
                    name = "Changed files",
                    cwd = root,
                    items = items,
                    show = require("aru.interface.picker").show,
                },
                window = { config = require("aru.interface.picker").window_config },
            })
        end)
    )
end

local request_id = 0
function M.find_changed_files()
    request_id = request_id + 1
    local current_request = request_id
    local cwd = vim.uv.cwd()
    local function active() return current_request == request_id and vim.uv.cwd() == cwd end

    local function find_git_files()
        vim.system(
            { "git", "rev-parse", "--show-toplevel" },
            { cwd = cwd, text = true },
            vim.schedule_wrap(function(result)
                if not active() then return end
                if result.code ~= 0 then
                    vim.notify("Not in a jj or Git repository", vim.log.levels.INFO)
                    return
                end
                changed_files(
                    result.stdout:gsub("\n$", ""),
                    { "git", "status", "--porcelain=v1", "-z", "--untracked-files=all" },
                    true,
                    active
                )
            end)
        )
    end

    if vim.fn.executable("jj") == 0 then
        find_git_files()
        return
    end

    vim.system(
        { "jj", "root" },
        { cwd = cwd, text = true },
        vim.schedule_wrap(function(result)
            if not active() then return end
            if result.code ~= 0 then
                find_git_files()
                return
            end
            changed_files(
                result.stdout:gsub("\n$", ""),
                { "jj", "diff", "-T", 'path ++ "\\0"' },
                false,
                active
            )
        end)
    )
end

return M
