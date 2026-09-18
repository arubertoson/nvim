vim.cmd("packadd blink.cmp")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local root

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            root = vim.fn.tempname()
            vim.fs.mkdir(vim.fs.joinpath(root, "src"), { parents = true })
            vim.fn.writefile({ "content" }, vim.fs.joinpath(root, "src", "child.lua"))
        end,
        post_case = function() vim.fn.delete(root, "rf") end,
    },
})

local function complete(line, bounds)
    local response
    local source = require("aru.cmp.path").new({
        reference_triggers = true,
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

T["path source"]["completes unprefixed relative paths"] = function()
    local response = complete("src/", { start_col = 5, length = 0 })

    MiniTest.expect.equality(
        vim.iter(response.items):any(function(item) return item.label == "child.lua" end),
        true
    )
end

T["path source"]["adds agent reference trigger characters"] = function()
    local source = require("aru.cmp.path").new({ reference_triggers = true })
    local triggers = source:get_trigger_characters()

    MiniTest.expect.equality(vim.tbl_contains(triggers, "@"), true)
    MiniTest.expect.equality(vim.tbl_contains(triggers, "`"), true)
end

return T
