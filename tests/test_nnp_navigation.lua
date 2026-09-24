pcall(vim.cmd, "packadd mini.nvim")
local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "tests/init.lua" })
            child.lua([[
                vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
                vim.cmd("packadd no-neck-pain.nvim")
                vim.o.columns = 210
                assert(require("no-neck-pain"))
                require("aru.workspace.layout")
                assert(vim.wait(1000, function()
                    return _G.NoNeckPain.state and _G.NoNeckPain.state.enabled
                end))
            ]])
        end,
        post_once = child.stop,
    },
})

T["native navigation through padding stays in the same tab"] = function()
    local result = child.lua([[
        vim.cmd.tabnew()
        local tab = vim.api.nvim_get_current_tabpage()
        local query = vim.api.nvim_get_current_win()
        assert(vim.wait(1000, function()
            local state = _G.NoNeckPain.state.tabs[tab]
            return state and state.wins.main.left ~= nil
        end))
        local left = _G.NoNeckPain.state.tabs[tab].wins.main.left
        vim.cmd("botright split")
        local result = vim.api.nvim_get_current_win()
        vim.cmd("wincmd J")
        local function press(keys)
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
        end

        vim.api.nvim_set_current_win(result)
        press("<C-w>k")
        local up = vim.wait(1000, function() return vim.api.nvim_get_current_win() == query end)
        local up_tab = vim.api.nvim_get_current_tabpage() == tab
        press("<C-w>h")
        local leftward = vim.wait(1000, function() return vim.api.nvim_get_current_win() == result end)
        return { up, up_tab, leftward, vim.api.nvim_get_current_tabpage() == tab,
            vim.api.nvim_win_is_valid(left) }
    ]])
    MiniTest.expect.equality(result, { true, true, true, true, true })
end

return T
