pcall(vim.cmd, "packadd mini.nvim")
local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local nnp
local enabled_on_load
local original_columns

local function enabled() return _G.NoNeckPain.state and _G.NoNeckPain.state.enabled end

local function wait_for(predicate) MiniTest.expect.equality(vim.wait(1000, predicate, 10), true) end

local T = MiniTest.new_set({
    hooks = {
        pre_once = function()
            vim.cmd("packadd no-neck-pain.nvim")
            original_columns = vim.o.columns
            vim.o.columns = 180
            require("aru.editor.keymaps")
            require("aru.workspace.layout")
            enabled_on_load = enabled() and #vim.api.nvim_tabpage_list_wins(0) > 1
            nnp = require("no-neck-pain")
        end,
        pre_case = function()
            nnp.enable()
            wait_for(function() return enabled() and #vim.api.nvim_tabpage_list_wins(0) > 1 end)
        end,
        post_case = function()
            if enabled() then require("no-neck-pain.main").disable("test_cleanup") end
            vim.cmd("silent! %bwipeout!")
        end,
        post_once = function()
            vim.o.columns = original_columns
            vim.api.nvim_del_augroup_by_name("AruNoNeckPainFiletypeLayout")
            vim.api.nvim_del_augroup_by_name("NoNeckPainAutocmd")
        end,
    },
})

T["initial layout is ready when its module loads"] = function()
    MiniTest.expect.equality(enabled_on_load, true)
end

T["closing a temporary file preserves the centered editing window"] = function()
    local win = vim.api.nvim_get_current_win()
    local temporary = vim.fn.tempname()
    local next_file = vim.fn.tempname()
    vim.cmd.edit(temporary)
    local buf = vim.api.nvim_get_current_buf()

    vim.cmd("normal ,c")

    MiniTest.expect.equality(vim.api.nvim_get_current_win(), win)
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(buf), false)
    MiniTest.expect.equality(enabled(), true)
    vim.cmd.edit(next_file)
    MiniTest.expect.equality(vim.api.nvim_get_current_win(), win)
    MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), next_file)

    nnp.toggle()
    wait_for(function() return not enabled() end)
    nnp.toggle()
    wait_for(function() return enabled() and #vim.api.nvim_tabpage_list_wins(0) > 1 end)
    MiniTest.expect.equality(vim.api.nvim_get_current_win(), win)
    MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), next_file)
end

T["closing an extra split still closes its window"] = function()
    vim.cmd.vsplit()
    local extra = vim.api.nvim_get_current_win()

    vim.cmd("normal ,c")

    MiniTest.expect.equality(vim.api.nvim_win_is_valid(extra), false)
    MiniTest.expect.equality(enabled(), true)
end

T["restarting layout recovers a missing editing window"] = function()
    local state = _G.NoNeckPain.state
    local tab = vim.api.nvim_get_current_tabpage()
    local main = state.tabs[tab].wins.main
    vim.api.nvim_win_close(main.curr, true)
    wait_for(function() return #vim.api.nvim_tabpage_list_wins(tab) == 1 end)

    local keys = vim.api.nvim_replace_termcodes(";wo", true, false, true)
    vim.api.nvim_feedkeys(keys, "xt", false)
    wait_for(function() return not enabled() end)

    vim.api.nvim_feedkeys(keys, "xt", false)
    wait_for(function()
        local current = _G.NoNeckPain.state
        local layout = current.tabs[tab]
        return current.enabled and layout and #vim.api.nvim_tabpage_list_wins(tab) > 1
    end)

    local recovered = _G.NoNeckPain.state.tabs[tab].wins.main
    local has_editing_window = false
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if win ~= recovered.left and win ~= recovered.right then has_editing_window = true end
    end
    MiniTest.expect.equality(has_editing_window, true)
end

T["restarting layout recomputes padding window width"] = function()
    local tab = vim.api.nvim_get_current_tabpage()
    local left = _G.NoNeckPain.state.tabs[tab].wins.main.left
    vim.api.nvim_win_set_width(left, 3)

    local keys = vim.api.nvim_replace_termcodes(";wo", true, false, true)
    vim.api.nvim_feedkeys(keys, "xt", false)
    wait_for(function() return not enabled() end)

    vim.api.nvim_feedkeys(keys, "xt", false)
    wait_for(function()
        local state = _G.NoNeckPain.state
        local layout = state.tabs[tab]
        return state.enabled and layout and layout.wins.main.left ~= left
    end)

    local resized = _G.NoNeckPain.state.tabs[tab].wins.main.left
    MiniTest.expect.equality(vim.api.nvim_win_get_width(resized) > 3, true)
end

return T
