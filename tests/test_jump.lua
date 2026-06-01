pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

require("aru.log").configure({
    level = vim.log.levels.ERROR,
    sinks = {},
})

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            vim.cmd("silent! %bwipeout!")
            package.loaded["aru.jump"] = nil
        end,
        post_case = function()
            local ok, jump = pcall(require, "aru.jump")
            if ok then pcall(jump.reset) end
            vim.cmd("silent! %bwipeout!")
        end,
    },
})

local tmp_root = vim.fn.tempname()
vim.fn.mkdir(tmp_root, "p")

local function temp_file(name, line_count)
    local path = tmp_root .. "/" .. name
    local lines = {}
    for i = 1, line_count do
        lines[i] = ("line %03d"):format(i)
    end
    vim.fn.writefile(lines, path)
    return path
end

local function edit(path)
    vim.cmd.edit(vim.fn.fnameescape(path))
    return vim.api.nvim_get_current_buf()
end

local function setup_jump(path)
    edit(path)

    local jump = require("aru.jump")
    jump.setup()

    local state = jump.buffers[path]
    MiniTest.expect.no_equality(state, nil)

    return jump, state
end

local function view_at(line)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    return vim.tbl_extend("force", {}, vim.fn.winsaveview(), { botline = vim.fn.line("w$") })
end

local function area_at(line)
    return {
        extmark_id = nil,
        view = view_at(line),
        semantic = nil,
    }
end

local function seed_history(state, lines, index)
    local entries = {}
    for i, line in ipairs(lines) do
        entries[i] = area_at(line)
    end

    state.history.entries = entries
    state.history.index = index
end

local function record_at(jump, state, line)
    jump._test.record_buffer_area(state, view_at(line))
end

T["buffer history"] = MiniTest.new_set()

T["buffer history"]["prev and next restore seeded areas"] = function()
    local path = temp_file("local-prev-next.lua", 260)
    local jump, state = setup_jump(path)
    seed_history(state, { 20, 100, 220 }, 2)

    jump.next()
    MiniTest.expect.equality(vim.fn.line("."), 220)
    MiniTest.expect.equality(state.history.index, 3)
    MiniTest.expect.equality(#state.history.entries, 3)

    jump.prev()
    MiniTest.expect.equality(vim.fn.line("."), 100)
    MiniTest.expect.equality(state.history.index, 2)
    MiniTest.expect.equality(#state.history.entries, 3)
end

T["buffer history"]["navigation does not record itself"] = function()
    local path = temp_file("local-navigation-quiet.lua", 260)
    local jump, state = setup_jump(path)
    seed_history(state, { 20, 100, 220 }, 3)

    jump.prev()

    MiniTest.expect.equality(vim.fn.line("."), 100)
    MiniTest.expect.equality(state.history.index, 2)
    MiniTest.expect.equality(#state.history.entries, 3)
end

T["buffer history"]["moving inside active area preserves forward history"] = function()
    local path = temp_file("local-update-keeps-forward.lua", 260)
    local jump, state = setup_jump(path)
    seed_history(state, { 20, 100, 220 }, 2)

    record_at(jump, state, 105)

    MiniTest.expect.equality(#state.history.entries, 3)
    MiniTest.expect.equality(state.history.index, 2)
    MiniTest.expect.equality(state.history.entries[2].view.lnum, 105)

    jump.next()
    MiniTest.expect.equality(vim.fn.line("."), 220)
    MiniTest.expect.equality(state.history.index, 3)
end

T["buffer history"]["moving to a new area from the middle branches history"] = function()
    local path = temp_file("local-branch.lua", 260)
    local jump, state = setup_jump(path)
    seed_history(state, { 20, 100, 220 }, 2)

    record_at(jump, state, 160)

    MiniTest.expect.equality(#state.history.entries, 3)
    MiniTest.expect.equality(state.history.index, 3)
    MiniTest.expect.equality(state.history.entries[1].view.lnum, 20)
    MiniTest.expect.equality(state.history.entries[2].view.lnum, 100)
    MiniTest.expect.equality(state.history.entries[3].view.lnum, 160)

    jump.next()
    MiniTest.expect.equality(vim.fn.line("."), 160)
    MiniTest.expect.equality(state.history.index, 3)
end

T["file history"] = MiniTest.new_set()

T["file history"]["file prev and next restore marked files"] = function()
    local path_a = temp_file("file-a.lua", 20)
    local path_b = temp_file("file-b.lua", 20)
    local jump = setup_jump(path_a)

    jump.file_mark()
    edit(path_b)
    jump.file_mark()

    jump.file_prev()
    MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), path_a)

    jump.file_next()
    MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), path_b)
end

T["file history"]["file marks dedupe recent paths"] = function()
    local path = temp_file("file-dedupe.lua", 20)
    local jump = setup_jump(path)

    jump.file_mark()
    jump.file_mark()

    MiniTest.expect.equality(#jump.f_hist.entries, 1)
    MiniTest.expect.equality(jump.f_hist.index, 1)
end

T["file history"]["untrackable buffers are not marked"] = function()
    local path = temp_file("file-untrackable.lua", 20)
    local jump = setup_jump(path)

    vim.bo.filetype = "fzf"
    jump.file_mark()

    MiniTest.expect.equality(#jump.f_hist.entries, 0)
    MiniTest.expect.equality(jump.f_hist.index, 0)
end

return T
