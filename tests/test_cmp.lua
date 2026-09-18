vim.cmd("packadd blink.cmp")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local root

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            root = vim.fn.tempname()
            vim.fs.mkdir(vim.fs.joinpath(root, "src"), { parents = true })
            vim.fn.writefile({
                "local function child()",
                "    return true",
                "end",
            }, vim.fs.joinpath(root, "src", "child.lua"))
        end,
        post_case = function()
            vim.cmd("silent! %bwipeout!")
            vim.fn.delete(root, "rf")
        end,
    },
})

local function complete(line, bounds)
    local response
    local source = require("aru.agent.completion.path").new({
        get_cwd = function() return root end,
    })
    source:get_completions({
        line = line,
        cursor = { 1, #line },
        bounds = bounds,
    }, function(result) response = result end)

    MiniTest.expect.equality(vim.wait(1000, function() return response ~= nil end), true)
    return response
end

T["path source"] = MiniTest.new_set()

T["path source"]["completes project-relative agent references"] = function()
    local response = complete("@src/ch", { start_col = 6, length = 2 })
    local child = vim.iter(response.items)
        :find(function(item) return item.label == "child.lua" end)

    MiniTest.expect.no_equality(child, nil)
    MiniTest.expect.equality(child.textEdit.range, {
        start = { line = 0, character = 5 },
        ["end"] = { line = 0, character = 7 },
    })
end

T["path source"]["ignores paths outside inline references"] = function()
    local response = complete("src/", { start_col = 5, length = 0 })
    MiniTest.expect.equality(response.items, {})
end

T["path source"]["adds agent reference trigger characters"] = function()
    local source = require("aru.agent.completion.path").new({})
    local triggers = source:get_trigger_characters()

    MiniTest.expect.equality(vim.tbl_contains(triggers, "@"), true)
end

T["symbol source"] = MiniTest.new_set()

T["symbol source"]["uses symbols from the shared context index"] = function()
    local path = vim.fs.joinpath(root, "src", "child.lua")
    local invocation_buf = vim.fn.bufadd(path)
    vim.fn.bufload(invocation_buf)
    vim.bo[invocation_buf].filetype = "lua"
    local source = require("aru.agent.completion.symbol").new({
        get_cwd = function() return root end,
        get_invocation_buf = function() return invocation_buf end,
    })
    local response
    local line = "@src/child.lua#chi"
    source:get_completions({
        line = line,
        cursor = { 1, #line },
    }, function(result) response = result end)

    MiniTest.expect.equality(response.items[1].label, "child")
    MiniTest.expect.equality(response.items[1].textEdit, {
        newText = "child",
        range = {
            start = { line = 0, character = 15 },
            ["end"] = { line = 0, character = 18 },
        },
    })
end

return T
