local MiniTest = require("mini.test")
local expect = MiniTest.expect.equality
local previous_statusline, previous_renderer, previous_parley

local function request_changed(status)
    vim.api.nvim_exec_autocmds("User", { pattern = "ParleyRequestChanged", data = status })
end

local function rendered() return vim.api.nvim_eval_statusline(_G.StatusLine.active(), {}).str end

local T = MiniTest.new_set({
    hooks = {
        pre_once = function()
            previous_statusline = vim.o.statusline
            previous_renderer = _G.StatusLine
            previous_parley = package.loaded["parley"]
            dofile("lua/aru/interface/statusline.lua")
        end,
        pre_case = function() request_changed({ phase = "idle", accepted = false }) end,
        post_once = function()
            vim.api.nvim_del_augroup_by_name("aru-statusline")
            vim.o.statusline = previous_statusline
            _G.StatusLine = previous_renderer
        end,
    },
})

T["request events update cached progress without loading Parley or taking focus"] = function()
    expect(rendered():find("Parley:", 1, true), nil)
    expect(package.loaded["parley"], previous_parley)
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()

    request_changed({ phase = "uploading", accepted = false })
    expect(rendered():find("Parley: uploading", 1, true) ~= nil, true)

    request_changed({ phase = "accepted", accepted = true, activity = "working" })
    expect(rendered():find("Parley: accepted / working", 1, true) ~= nil, true)
    expect(vim.api.nvim_get_current_win(), window)
    expect(vim.api.nvim_get_current_buf(), buffer)

    request_changed({ phase = "idle", accepted = false })
    expect(rendered():find("Parley:", 1, true), nil)
end

T["delivery failure preserves the completed reviewer outcome"] = function()
    local outcome = { id = "outcome-1", status = "completed", detail = vim.NIL, createdAt = 1 }
    request_changed({ phase = "completed", accepted = true, outcome = outcome })
    expect(rendered():find("Parley: completed", 1, true) ~= nil, true)

    request_changed({
        phase = "failed",
        accepted = true,
        outcome = outcome,
        receipts = "unknown",
        error = "Receipt acknowledgment lost",
    })
    expect(rendered():find("Parley: completed / delivery failed", 1, true) ~= nil, true)
end

return T
