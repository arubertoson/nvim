local MiniTest = _G.MiniTest or require("mini.test")
local child = MiniTest.new_child_neovim()
local test_init = vim.fn.fnamemodify("tests/init.lua", ":p")
local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", test_init })
            child.lua([[
                vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
                vim.cmd("packadd mini.nvim")
                require("mini.pick").setup()
            ]])
        end,
        post_once = child.stop,
    },
})

local function run(args, root)
    local result = vim.system(args, { cwd = root, text = true }):wait()
    if result.code ~= 0 then error(table.concat(args, " ") .. ": " .. (result.stderr or "")) end
end

local function write(root, name) vim.fn.writefile({ "content" }, vim.fs.joinpath(root, name)) end

local function pick_files(root)
    return child.lua(
        [[
        vim.api.nvim_set_current_dir(...)
        local picker = require("mini.pick")
        local items
        local function collect()
            if not picker.is_picker_active() or #picker.get_picker_items() == 0 then
                vim.defer_fn(collect, 10)
                return
            end
            items = picker.get_picker_items()
            picker.stop()
        end
        vim.defer_fn(collect, 10)
        require("aru.workspace.changed_files").find_changed_files()
        assert(vim.wait(4000, function() return items ~= nil end, 20))
        local paths = {}
        for _, item in ipairs(items) do
            paths[item.text] = item.path
        end
        return paths
    ]],
        { root }
    )
end

T["Git lists working-tree, staged and untracked paths without deleted files"] = function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    run({ "git", "init", "-q" }, root)
    write(root, "modified")
    write(root, "staged")
    write(root, "deleted")
    write(root, "old name")
    run({ "git", "add", "-A" }, root)
    run({
        "git",
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "-qm",
        "base",
    }, root)
    write(root, "modified")
    vim.fn.writefile({ "new content" }, vim.fs.joinpath(root, "modified"))
    vim.fn.writefile({ "new content" }, vim.fs.joinpath(root, "staged"))
    run({ "git", "add", "staged" }, root)
    vim.fn.delete(vim.fs.joinpath(root, "deleted"))
    run({ "git", "mv", "old name", "new name" }, root)
    write(root, "new\nline")
    local paths = pick_files(root)
    MiniTest.expect.equality(paths, {
        modified = vim.fs.joinpath(root, "modified"),
        staged = vim.fs.joinpath(root, "staged"),
        ["new name"] = vim.fs.joinpath(root, "new name"),
        ["new\nline"] = vim.fs.joinpath(root, "new\nline"),
    })
    vim.fn.delete(root, "rf")
end

local function jj_working_change(colocated)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    if colocated then
        run({ "git", "init", "-q" }, root)
        run({ "jj", "git", "init", "--colocate" }, root)
    else
        run({ "jj", "git", "init" }, root)
    end
    write(root, "previous")
    run({ "jj", "commit", "-m", "previous" }, root)
    write(root, "current")
    write(root, "new\nline")
    local paths = pick_files(root)
    MiniTest.expect.equality(paths, {
        current = vim.fs.joinpath(root, "current"),
        ["new\nline"] = vim.fs.joinpath(root, "new\nline"),
    })
    vim.fn.delete(root, "rf")
end

T["jj lists only working-copy changes, including newline paths"] = function()
    jj_working_change(false)
end
T["colocated jj uses working-copy changes instead of Git status"] = function()
    jj_working_change(true)
end

return T
