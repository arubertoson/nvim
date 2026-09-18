vim.cmd("packadd blink.cmp")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local root

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            root = vim.fn.tempname()
            vim.fs.mkdir(vim.fs.joinpath(root, "src", "deep"), { parents = true })
            vim.fs.mkdir(vim.fs.joinpath(root, ".hidden"), { parents = true })
            vim.fn.writefile({ "content" }, vim.fs.joinpath(root, "src", "child.lua"))
            vim.fn.writefile({ "content" }, vim.fs.joinpath(root, "src", "deep", "list.zig"))
            vim.fn.writefile({ "content" }, vim.fs.joinpath(root, ".hidden", "secret.zig"))
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

local function complete_files(line)
    local response
    local source = require("aru.cmp.files").new({
        get_cwd = function() return root end,
    })
    source:get_completions({
        line = line,
        cursor = { 1, #line },
        bounds = { start_col = 2, length = #line - 1 },
    }, function(result) response = result end)

    MiniTest.expect.equality(vim.wait(1000, function() return response ~= nil end), true)
    return response
end

T["project file source"] = MiniTest.new_set()

T["project file source"]["fuzzy matches files at any depth"] = function()
    local response = complete_files("@list.zig")

    MiniTest.expect.equality(response.items[1].label, "src/deep/list.zig")
    MiniTest.expect.equality(response.items[1].textEdit, {
        newText = "src/deep/list.zig",
        range = {
            start = { line = 0, character = 1 },
            ["end"] = { line = 0, character = 9 },
        },
    })
end

T["project file source"]["includes hidden files"] = function()
    local response = complete_files("@secret.zig")

    MiniTest.expect.equality(response.items[1].label, ".hidden/secret.zig")
end

T["project file source"]["only completes marked references"] = function()
    local response = complete_files("list.zig")

    MiniTest.expect.equality(response.items, {})
end

T["marked buffer source"] = MiniTest.new_set()

T["marked buffer source"]["only completes hash references"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "activebufferword" })

    local source = require("aru.cmp.buffer").new({
        get_bufnrs = function() return { bufnr } end,
    })
    local response
    source:get_completions({
        line = "#active",
        cursor = { 1, 7 },
        bounds = { start_col = 2, length = 6 },
    }, function(result) response = result end)

    MiniTest.expect.equality(vim.wait(1000, function() return response ~= nil end), true)
    MiniTest.expect.equality(
        vim.iter(response.items):any(function(item) return item.label == "activebufferword" end),
        true
    )
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["marked buffer source"]["returns nothing without a hash reference"] = function()
    local source = require("aru.cmp.buffer").new({ get_bufnrs = function() return {} end })
    local response
    source:get_completions({
        line = "active",
        cursor = { 1, 6 },
        bounds = { start_col = 1, length = 6 },
    }, function(result) response = result end)

    MiniTest.expect.equality(response.items, {})
    MiniTest.expect.equality(source:get_trigger_characters(), { "#" })
end

return T
