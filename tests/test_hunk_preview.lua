local MiniTest = _G.MiniTest or require("mini.test")
local child = MiniTest.new_child_neovim()
local packpath, config_root = vim.o.packpath, vim.fn.getcwd()
local root

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            root = vim.fn.tempname()
            child.restart({ "-u", "NONE", "--noplugin" })
            child.lua(
                [[
                local packpath, config_root, root = ...
                vim.o.packpath = packpath
                vim.opt.runtimepath:append(config_root)
                for _, name in ipairs({ "async.nvim", "vclib.nvim", "vcsigns.nvim" }) do
                    vim.cmd.packadd(name)
                end
                vim.fn.mkdir(root, "p")
                local function git(args)
                    local result = vim.system(vim.list_extend({ "git" }, args), {
                        cwd = root, text = true,
                    }):wait()
                    assert(result.code == 0, result.stderr)
                end
                git({ "init", "-q" })
                local base = {}
                for i = 1, 15 do base[i] = "line " .. i end
                local file = root .. "/file.txt"
                vim.fn.writefile(base, file)
                git({ "add", "file.txt" })
                git({ "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                    "commit", "-qm", "base" })
                local changed = vim.deepcopy(base)
                changed[3], changed[12] = "changed three", "changed twelve"
                vim.fn.writefile(changed, file)
                vim.cmd.edit(file)
                -- Deferred configuration loads after the initial BufEnter.
                dofile("lua/aru/workspace/vc_signs.lua")

                local signs = vim.api.nvim_create_namespace("vcsigns")
                fixture = {
                    buf = vim.api.nvim_get_current_buf(),
                    ns = vim.api.nvim_create_namespace("aru_hunk_preview"),
                    base = base,
                    git = git,
                }
                assert(vim.wait(4000, function()
                    return #vim.api.nvim_buf_get_extmarks(fixture.buf, signs, 0, -1, {}) > 0
                end, 20), "Deferred VCSigns setup did not initialize the open buffer")
            ]],
                { packpath, config_root, root }
            )
        end,
        post_case = function()
            child.stop()
            vim.fn.delete(root, "rf")
        end,
    },
})

local function space(line)
    child.lua(
        [[
        local line = ...
        if line then vim.api.nvim_win_set_cursor(0, { line, 0 }) end
        vim.api.nvim_feedkeys(" ", "xt", false)
    ]],
        { line }
    )
end

local function visible()
    return child.lua_get("#vim.api.nvim_buf_get_extmarks(fixture.buf, fixture.ns, 0, -1, {}) > 0")
end

local function deleted_lines()
    return child.lua([[
        local result = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(
            fixture.buf, fixture.ns, 0, -1, { details = true }
        )) do
            for _, line in ipairs(mark[4].virt_lines or {}) do
                local text = {}
                for _, chunk in ipairs(line) do text[#text + 1] = chunk[1] end
                result[#result + 1] = table.concat(text)
            end
        end
        return result
    ]])
end

T["Space toggles only the selected hunk and switches between hunks"] = function()
    space(3)
    MiniTest.expect.equality(deleted_lines(), { "line 3" })
    space()
    MiniTest.expect.equality(visible(), false)
    space(3)
    space(12)
    MiniTest.expect.equality(deleted_lines(), { "line 12" })
    child.lua("vim.api.nvim_win_set_cursor(0, { 1, 0 })")
    MiniTest.expect.equality(visible(), true)
    space()
    MiniTest.expect.equality(visible(), false)
end

T["inline rendering supports boundary deletions and added-only hunks"] = function()
    child.lua([[
        vim.api.nvim_buf_set_lines(fixture.buf, 0, -1, false, vim.list_slice(fixture.base, 2, 14))
    ]])
    space(1)
    MiniTest.expect.equality(deleted_lines(), { "line 1" })
    MiniTest.expect.equality(
        child.lua_get([[
        vim.api.nvim_buf_get_extmarks(fixture.buf, fixture.ns, 0, -1, { details = true })[1][4].virt_lines_above
    ]]),
        true
    )
    space(13)
    MiniTest.expect.equality(deleted_lines(), { "line 15" })
    child.lua([[
        vim.api.nvim_buf_set_lines(fixture.buf, 0, -1, false, fixture.base)
        vim.api.nvim_buf_set_lines(fixture.buf, 5, 5, false, { "added one", "added two" })
    ]])
    space(6)
    MiniTest.expect.equality(visible(), true)
    MiniTest.expect.equality(deleted_lines(), {})
    space(7)
    MiniTest.expect.equality(visible(), false)
end

T["edits, reloads and window changes dismiss the snapshot"] = function()
    space(3)
    child.lua("vim.api.nvim_buf_set_lines(fixture.buf, 2, 3, false, { 'new edit' })")
    MiniTest.expect.equality(visible(), false)
    space(3)
    MiniTest.expect.equality(visible(), true)
    child.cmd("edit!")
    MiniTest.expect.equality(visible(), false)
    space(3)
    MiniTest.expect.equality(visible(), true)
    child.cmd("vsplit")
    MiniTest.expect.equality(visible(), false)
end

T["delayed text events and autosave do not dismiss a new snapshot"] = function()
    child.lua([[
        dofile("lua/aru/editor/autosave.lua")
        vim.api.nvim_buf_set_lines(fixture.buf, 2, 3, false, { "edited before preview" })
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        vim.api.nvim_feedkeys(" ", "xt", false)
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = fixture.buf })
        assert(vim.wait(2000, function() return not vim.bo[fixture.buf].modified end, 20),
            "Autosave did not finish")
    ]])
    MiniTest.expect.equality(deleted_lines(), { "line 3" })
    space()
    MiniTest.expect.equality(visible(), false)
end

T["repository refresh leaves the snapshot until dismissed"] = function()
    space(3)
    child.lua([[
        fixture.git({ "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "commit", "-qam", "next" })
        vim.api.nvim_exec_autocmds("CursorHold", { buffer = fixture.buf })
        local signs = vim.api.nvim_create_namespace("vcsigns")
        assert(vim.wait(4000, function()
            return #vim.api.nvim_buf_get_extmarks(fixture.buf, signs, 0, -1, {}) == 0
        end, 20), "VCSigns did not refresh")
    ]])
    MiniTest.expect.equality(deleted_lines(), { "line 3" })
    space()
    MiniTest.expect.equality(visible(), false)
    space()
    MiniTest.expect.equality(visible(), false)
end

return T
