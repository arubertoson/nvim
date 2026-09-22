pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local scratch

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["aru.tools.lua_scratch"] = nil
            scratch = require("aru.tools.lua_scratch")
        end,
        post_case = function()
            scratch.close()
            vim.cmd("silent! %bwipeout!")
        end,
    },
})

local function is_named(buf, name) return vim.api.nvim_buf_get_name(buf):sub(-#name) == name end

local function window_named(name)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if is_named(buf, name) then return win end
    end
end

local function buffer_named(name)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and is_named(buf, name) then return buf end
    end
end

local function output_text()
    local buf = assert(buffer_named("Lua Scratch Output"))
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function visual_callback()
    local mapping = vim.fn.maparg("<leader>rs", "x", false, true)
    return assert(mapping.callback)
end

T["reconstructs the layout when only output survives"] = function()
    scratch.open()
    vim.api.nvim_win_close(assert(window_named("Lua Scratch")), true)

    scratch.open()

    MiniTest.expect.equality(type(window_named("Lua Scratch")), "number")
    MiniTest.expect.equality(type(window_named("Lua Scratch Output")), "number")
end

T["does not close a window that no longer displays an owned buffer"] = function()
    scratch.open()
    local scratch_win = assert(window_named("Lua Scratch"))
    local replacement = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(scratch_win, replacement)

    scratch.close()

    MiniTest.expect.equality(vim.api.nvim_win_is_valid(scratch_win), true)
    MiniTest.expect.equality(vim.api.nvim_win_get_buf(scratch_win), replacement)
end

T["runs linewise visual selections"] = function()
    scratch.open()
    local win = assert(window_named("Lua Scratch"))
    local buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'print("one")', 'print("two")' })
    vim.api.nvim_set_current_win(win)
    vim.cmd([[execute "normal! ggVj"]])

    visual_callback()()

    MiniTest.expect.equality(output_text():find("one", 1, true) ~= nil, true)
    MiniTest.expect.equality(output_text():find("two", 1, true) ~= nil, true)
end

T["runs blockwise visual selections"] = function()
    scratch.open()
    local win = assert(window_named("Lua Scratch"))
    local buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'xxprint("one")yy', 'xxprint("two")yy' })
    vim.api.nvim_set_current_win(win)
    vim.cmd([[execute "normal! gg2l\<C-v>j11l"]])

    visual_callback()()

    MiniTest.expect.equality(output_text():find("one", 1, true) ~= nil, true)
    MiniTest.expect.equality(output_text():find("two", 1, true) ~= nil, true)
end

T["global inspector preserves nil arguments"] = function()
    P(1, nil, 3)

    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "1", "nil", "3" })
end

return T
