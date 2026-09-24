pcall(vim.cmd, "packadd mini.nvim")
local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local T = MiniTest.new_set()
local config_root = vim.fn.getcwd()
local tracks_root = vim.fs.normalize(config_root .. "/../tracks.nvim")

local function project()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.git", "p")
    local jj = root .. "/.workspaces/child"
    vim.fn.mkdir(jj .. "/.jj", "p")
    local state = vim.fn.tempname()
    vim.fn.mkdir(state, "p")
    for _, name in ipairs({ "a", "b" }) do
        vim.fn.writefile({ "first", "second", "third" }, jj .. "/" .. name .. ".lua")
    end
    local init = root .. "/test-init.lua"
    vim.fn.writefile({
        ("vim.opt.runtimepath:prepend(%q)"):format(tracks_root),
        ("vim.opt.runtimepath:prepend(%q)"):format(config_root),
        'require("aru.workspace.sessions")',
    }, init)
    return { root = root, jj = jj, state = state, init = init }
end

local function launch(p, args, commands)
    local output = vim.fn.tempname()
    local argv = { vim.v.progpath, "--headless", "--noplugin", "-u", p.init }
    vim.list_extend(argv, args)
    if commands then vim.list_extend(argv, { "-c", commands }) end
    vim.list_extend(argv, {
        "-c",
        ("lua vim.fn.writefile({vim.json.encode({cwd=vim.uv.cwd(),path=vim.api.nvim_buf_get_name(0),line=vim.api.nvim_win_get_cursor(0)[1],history=require('tracks.file_jump').snapshot()})},%q)"):format(
            output
        ),
        "+qa!",
    })
    local result = vim.system(argv, {
        cwd = p.jj,
        env = { XDG_STATE_HOME = p.state },
        text = true,
    }):wait()
    MiniTest.expect.equality(result.code, 0)
    return vim.json.decode(vim.fn.readfile(output)[1])
end

T["jj resume and file navigation survive restart"] = function()
    local p = project()
    local first = launch(p, {}, "edit a.lua | call cursor(2, 1) | edit b.lua | call cursor(3, 1)")
    MiniTest.expect.equality(first.cwd, p.jj)
    MiniTest.expect.equality(#first.history.entries, 2)

    local second = launch(p, {}, "lua assert(require('tracks.file_jump').prev())")
    MiniTest.expect.equality(second.path, p.jj .. "/a.lua")
    MiniTest.expect.equality(second.line, 2)
    MiniTest.expect.equality(#second.history.entries, 2)

    local dot = launch(p, { "." })
    MiniTest.expect.equality(dot.path, p.jj .. "/a.lua")
    MiniTest.expect.equality(dot.line, 2)
    MiniTest.expect.equality(dot.cwd, p.jj)

    local explicit = launch(p, { "b.lua" })
    MiniTest.expect.equality(explicit.path, p.jj .. "/b.lua")
end

T["outside-workspace file visits resume and navigate"] = function()
    local p = project()
    local external = p.root .. "/zig-source.zig"
    vim.fn.writefile({ "one", "two", "three" }, external)

    launch(
        p,
        {},
        ("edit a.lua | edit %s | call cursor(3, 1)"):format(vim.fn.fnameescape(external))
    )
    local resumed = launch(p, {})
    MiniTest.expect.equality(resumed.path, external)
    MiniTest.expect.equality(resumed.line, 3)
    MiniTest.expect.equality(#resumed.history.entries, 2)
    MiniTest.expect.equality(resumed.history.entries[1].path, p.jj .. "/a.lua")
end

T["changing cwd switches trails without leaking visits"] = function()
    local p = project()
    local other = p.root .. "/other"
    vim.fn.mkdir(other .. "/.jj", "p")
    vim.fn.writefile({ "one", "two" }, other .. "/c.lua")
    launch(p, {}, "edit a.lua | call cursor(2, 1)")

    local switched = launch(p, {}, ("cd %s | edit c.lua"):format(vim.fn.fnameescape(other)))
    MiniTest.expect.equality(switched.cwd, other)
    MiniTest.expect.equality(#switched.history.entries, 1)
    MiniTest.expect.equality(switched.history.entries[1].path, other .. "/c.lua")

    local original = launch(p, {})
    MiniTest.expect.equality(original.path, p.jj .. "/a.lua")
    MiniTest.expect.equality(#original.history.entries, 1)
end

T["window-local cwd changes and window switching keep scopes separate"] = function()
    local p = project()
    local other = p.root .. "/other"
    vim.fn.mkdir(other .. "/.jj", "p")
    vim.fn.writefile({ "one", "two" }, other .. "/c.lua")

    local switched = launch(
        p,
        {},
        ("edit a.lua | split | lcd %s | edit c.lua"):format(vim.fn.fnameescape(other))
    )
    MiniTest.expect.equality(switched.cwd, other)
    MiniTest.expect.equality(switched.history.entries[1].path, other .. "/c.lua")

    local back = launch(
        p,
        {},
        ("edit a.lua | split | lcd %s | edit c.lua | wincmd w"):format(vim.fn.fnameescape(other))
    )
    MiniTest.expect.equality(back.cwd, p.jj)
    MiniTest.expect.equality(#back.history.entries, 1)
    MiniTest.expect.equality(back.history.entries[1].path, p.jj .. "/a.lua")
end

T["focused tool and missing saved file do not create buffers"] = function()
    local p = project()
    launch(p, {}, "edit a.lua | call cursor(2, 1) | enew | setlocal buftype=nofile")
    local resumed = launch(p, {})
    MiniTest.expect.equality(resumed.path, p.jj .. "/a.lua")
    MiniTest.expect.equality(resumed.line, 2)

    vim.uv.fs_unlink(p.jj .. "/a.lua")
    local missing = launch(p, {})
    MiniTest.expect.equality(missing.path, "")
    MiniTest.expect.equality(vim.uv.fs_stat(p.jj .. "/a.lua"), nil)
end

return T
