vim.cmd("packadd async.nvim")
vim.cmd("packadd vclib.nvim")
vim.cmd("packadd vcsigns.nvim")
vim.g.mapleader = " "
dofile("lua/aru/workspace/vc_signs.lua")

local MiniTest = _G.MiniTest or require("mini.test")
local T = MiniTest.new_set()

local function run(args, root)
    local result = vim.system(args, { cwd = root, text = true }):wait()
    if result.code ~= 0 then error(table.concat(args, " ") .. ": " .. (result.stderr or "")) end
end

local function lines()
    local result = {}
    for i = 1, 15 do
        result[i] = "line " .. i
    end
    return result
end

local function make_repo(kind)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    if kind ~= "jj" then
        run({ "git", "init", "-b", "main" }, root)
        run({ "git", "config", "user.name", "Test" }, root)
        run({ "git", "config", "user.email", "test@example.invalid" }, root)
    end
    if kind == "colocated" then
        run({ "jj", "git", "init", "--colocate" }, root)
    elseif kind == "jj" then
        run({ "jj", "git", "init" }, root)
    end
    local file = vim.fs.joinpath(root, "file.txt")
    vim.fn.writefile(lines(), file)
    if kind == "git" then
        run({ "git", "add", "file.txt" }, root)
        run({ "git", "commit", "-m", "base" }, root)
    else
        run({ "jj", "commit", "-m", "base" }, root)
    end
    local changed = lines()
    changed[3] = "committed change"
    vim.fn.writefile(changed, file)
    if kind == "git" then
        run({ "git", "commit", "-am", "second" }, root)
    else
        run({ "jj", "commit", "-m", "second" }, root)
    end
    changed[12] = "working change"
    vim.fn.writefile(changed, file)
    return root, file
end

local ns = vim.api.nvim_create_namespace("vcsigns")
local function sign_lines(bufnr)
    local result = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
        if mark[4].sign_text then result[mark[2] + 1] = true end
    end
    return result
end

local function exercise(kind)
    local root, file = make_repo(kind)
    vim.cmd.edit(file)
    local bufnr = vim.api.nvim_get_current_buf()
    MiniTest.expect.equality(
        vim.wait(4000, function()
            local signs = sign_lines(bufnr)
            return signs[3] and signs[12]
        end, 20),
        true
    )
    MiniTest.expect.equality(sign_lines(bufnr), { [3] = true, [12] = true })

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd.normal("]c")
    MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0)[1], 3)
    vim.cmd.normal("]c")
    MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0)[1], 12)
    vim.cmd.normal("[c")
    MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0)[1], 3)
    vim.cmd.normal(" hr")
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(bufnr, 2, 3, false)[1], "line 3")
    vim.cmd("bdelete!")
    vim.fn.delete(root, "rf")
end

T["Git compares against HEAD~1 with signs, navigation and undo"] = function() exercise("git") end
T["jj signs, navigation and undo"] = function() exercise("jj") end
T["colocated jj takes precedence over Git"] = function() exercise("colocated") end

return T
