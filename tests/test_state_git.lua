pcall(function() vim.cmd("packadd mini.nvim") end)

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function() package.loaded["aru.state.git"] = nil end,
        post_case = function()
            local ok, git = pcall(require, "aru.state.git")
            if ok then git._test.reset() end
        end,
    },
})

local function sh(args, cwd)
    local result = vim.system(args, { cwd = cwd, text = true }):wait()
    if result.code ~= 0 then
        error(("command failed: %s\n%s"):format(table.concat(args, " "), result.stderr or ""))
    end
    return result
end

local function tmpdir()
    local path = vim.fn.tempname()
    vim.fn.mkdir(path, "p")
    return path
end

local function git_repo()
    local root = tmpdir()
    sh({ "git", "init", "-b", "main" }, root)
    sh({ "git", "config", "user.email", "test@example.invalid" }, root)
    sh({ "git", "config", "user.name", "Test" }, root)
    vim.fn.writefile({ "hello" }, vim.fs.joinpath(root, "file.txt"))
    sh({ "git", "add", "file.txt" }, root)
    sh({ "git", "commit", "-m", "initial" }, root)
    return root
end

local function wait_until(fn)
    local ok = vim.wait(1000, fn, 10)
    MiniTest.expect.equality(ok, true)
end

T["sync helpers expose git scope"] = function()
    local git = require("aru.git")
    local root = git_repo()
    local file = vim.fs.joinpath(root, "file.txt")

    local scope = git.scope_for(file)
    MiniTest.expect.equality(scope.root, vim.fs.normalize(vim.fs.abspath(root)))
    MiniTest.expect.equality(scope.branch, "main")
end

T["sync helpers report detached head hash"] = function()
    local git = require("aru.git")
    local root = git_repo()
    local commit = vim.trim(sh({ "git", "rev-parse", "HEAD" }, root).stdout)
    sh({ "git", "checkout", "--detach", commit }, root)

    MiniTest.expect.equality(git.branch_sync(root), commit:sub(1, 12))
end

T["branch_for is cache-only and refreshes asynchronously"] = function()
    local git = require("aru.state.git")
    local root = git_repo()

    MiniTest.expect.equality(git.branch_for(root), nil)
    wait_until(function() return git.branch_for(root) == "main" end)
    MiniTest.expect.equality(git._test.state[root].head_exists, true)
end

T["refresh callback receives branch"] = function()
    local git = require("aru.state.git")
    local root = git_repo()
    local seen

    git.refresh(root, function(branch) seen = branch end)
    wait_until(function() return seen == "main" end)
end

T["non-git directories stay nil and do not create watchers"] = function()
    local git = require("aru.state.git")
    local root = tmpdir()
    local seen = "unset"

    git.refresh(root, function(branch) seen = branch end)

    MiniTest.expect.equality(seen, nil)
    MiniTest.expect.equality(git.branch_for(root), nil)
    MiniTest.expect.equality(git._test.state[root].head_exists, false)
    MiniTest.expect.equality(git._test.state[root].watcher, nil)
end

T["detached HEAD reports nil"] = function()
    local git = require("aru.state.git")
    local root = git_repo()
    local commit = vim.trim(sh({ "git", "rev-parse", "HEAD" }, root).stdout)
    sh({ "git", "checkout", "--detach", commit }, root)

    local seen = "unset"
    git.refresh(root, function(branch) seen = branch end)
    wait_until(function() return seen == nil end)
    MiniTest.expect.equality(git.branch_for(root), nil)
end

T["watcher cleanup removes watcher handles"] = function()
    local git = require("aru.state.git")
    local root = git_repo()

    git.refresh(root)
    wait_until(
        function() return git._test.state[root] and git._test.state[root].watcher ~= nil end
    )

    git._test.reset()
    MiniTest.expect.equality(next(git._test.state), nil)
end

return T
