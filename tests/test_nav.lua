pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            vim.cmd("silent! %bwipeout!")
            package.loaded["aru.nav.active"] = nil
            package.loaded["aru.nav.buffers"] = nil
        end,
        post_case = function()
            vim.cmd("silent! %bwipeout!")
        end,
    },
})

local tmp_root = vim.fn.tempname()
vim.fn.mkdir(tmp_root, "p")

local function temp_project(name, branch)
    local root = tmp_root .. "/" .. name
    vim.fn.mkdir(root .. "/.git", "p")
    vim.fn.writefile({ "ref: refs/heads/" .. (branch or "main") }, root .. "/.git/HEAD")
    return root
end

local function temp_file(root, name)
    local path = root .. "/" .. name
    vim.fn.writefile({ name }, path)
    return path
end

local function edit(path)
    vim.cmd.edit(vim.fn.fnameescape(path))
    return vim.api.nvim_get_current_buf()
end

local function setup_active(storage)
    local active = require("aru.nav.active")
    active.setup({ storage_path = storage })
    return active
end

T["active files"] = MiniTest.new_set()

T["active files"]["compacts on removal"] = function()
    local root = temp_project("active-compact", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")

    edit(a)
    local active = setup_active(storage)
    active.add()

    edit(b)
    active.add()

    active.remove(1)

    MiniTest.expect.equality(#active.items(), 1)
    MiniTest.expect.equality(active.items()[1].path, vim.fs.normalize(b))
end

T["active files"]["does not grow past max files"] = function()
    local root = temp_project("active-max", "main")
    local storage = root .. "/active.json"
    local active

    for i = 1, 4 do
        edit(temp_file(root, ("%d.lua"):format(i)))
        active = active or setup_active(storage)
        active.add()
    end

    MiniTest.expect.equality(#active.items(), 3)
end

T["active files"]["persists by root and branch"] = function()
    local root = temp_project("active-scope", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")

    edit(a)
    local active = setup_active(storage)
    active.add()
    MiniTest.expect.equality(#active.items(), 1)

    package.loaded["aru.nav.active"] = nil
    active = setup_active(storage)
    MiniTest.expect.equality(#active.items(), 1)

    vim.fn.writefile({ "ref: refs/heads/feature" }, root .. "/.git/HEAD")
    package.loaded["aru.nav.active"] = nil
    active = setup_active(storage)
    MiniTest.expect.equality(#active.items(), 0)
end

T["buffer cache"] = MiniTest.new_set()

T["buffer cache"]["prunes cold unpinned file buffers"] = function()
    local root = temp_project("buffers-prune", "main")
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")
    local c = temp_file(root, "c.lua")

    local buf_a = edit(a)
    local buffers = require("aru.nav.buffers")
    buffers.setup({
        max_buffers = 2,
        is_pinned = function(path) return path == vim.fs.normalize(a) end,
    })

    local buf_b = edit(b)
    edit(c)
    buffers.prune()

    MiniTest.expect.equality(vim.api.nvim_buf_is_loaded(buf_a), true)
    MiniTest.expect.equality(vim.api.nvim_buf_is_loaded(buf_b), false)
end

return T
