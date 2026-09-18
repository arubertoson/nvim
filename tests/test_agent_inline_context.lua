pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local root
local invocation_buf

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["aru.agent.context"] = nil
            root = vim.fn.tempname()
            vim.fs.mkdir(vim.fs.joinpath(root, "lua"), { parents = true })
            vim.fn.writefile({
                "local M = {}",
                "",
                "function M.send(value)",
                "    return value",
                "end",
                "",
                "return M",
            }, vim.fs.joinpath(root, "lua", "agent.lua"))
            vim.cmd("enew!")
            invocation_buf = vim.api.nvim_get_current_buf()
        end,
        post_case = function()
            vim.cmd("silent! %bwipeout!")
            vim.fn.delete(root, "rf")
        end,
    },
})

T["reference parser"] = MiniTest.new_set()

T["reference parser"]["recognizes every form with prose boundaries"] = function()
    local parser = require("aru.agent.reference")
    local refs = parser.parse(
        "Compare `@lua/agent.lua#M::send` with (@lua/agent.lua:2-4), @#send and @lua/agent.lua.",
        nil
    )

    MiniTest.expect.equality(vim.tbl_map(function(ref) return ref.raw end, refs), {
        "@lua/agent.lua#M::send",
        "@lua/agent.lua:2-4",
        "@#send",
        "@lua/agent.lua",
    })
    MiniTest.expect.equality(refs[1].selector, { kind = "symbol", name = "M::send" })
    MiniTest.expect.equality(refs[2].selector, {
        kind = "lines",
        start_line = 2,
        end_line = 4,
    })
end

T["reference parser"]["ignores email addresses"] = function()
    local refs =
        require("aru.agent.reference").parse("mail dev@example.com about @lua/agent.lua", nil)
    MiniTest.expect.equality(#refs, 1)
    MiniTest.expect.equality(refs[1].raw, "@lua/agent.lua")
end

T["reference parser"]["uses the cursor to classify incomplete syntax"] = function()
    local parser = require("aru.agent.reference")
    local incomplete = "@lua/agent.lua:2-"
    local editing = parser.parse(incomplete, { 0, #incomplete })[1]
    local left = parser.parse(incomplete .. " next", { 0, #incomplete + 5 })[1]

    MiniTest.expect.equality(editing.state, "editing")
    MiniTest.expect.equality(left.state, "unresolved")
end

T["context resolver"] = MiniTest.new_set()

local function resolve(text, cursor)
    return require("aru.agent.context").resolve(text, cursor, root, invocation_buf)
end

T["context resolver"]["resolves whole files and inclusive ranges"] = function()
    local refs = resolve("@lua/agent.lua @lua/agent.lua:3-5", nil)

    MiniTest.expect.equality(refs[1].state, "resolved")
    MiniTest.expect.equality(refs[1].context.whole_file, true)
    MiniTest.expect.equality(refs[2].context.text, "function M.send(value)\n    return value\nend")
    MiniTest.expect.equality({ refs[2].context.start_line, refs[2].context.end_line }, { 3, 5 })
end

T["context resolver"]["loaded unsaved contents win over disk"] = function()
    local path = vim.fs.joinpath(root, "lua", "agent.lua")
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "unsaved", "contents" })

    local ref = resolve("@lua/agent.lua", nil)[1]
    MiniTest.expect.equality(ref.context.text, "unsaved\ncontents")
end

T["context resolver"]["editing a resolved file into a selector drops stale context"] = function()
    local whole = resolve("@lua/agent.lua", { 0, 14 })[1]
    local editing = resolve("@lua/agent.lua#", { 0, 15 })[1]

    MiniTest.expect.equality(whole.state, "resolved")
    MiniTest.expect.equality(editing.state, "editing")
    MiniTest.expect.equality(editing.context, nil)
end

T["context resolver"]["invalid ranges are unresolved even under the cursor"] = function()
    local reversed = resolve("@lua/agent.lua:5-2", { 0, 18 })[1]
    local outside = resolve("@lua/agent.lua:1-99", { 0, 19 })[1]

    MiniTest.expect.equality(reversed.state, "unresolved")
    MiniTest.expect.equality(outside.state, "unresolved")
end

T["context resolver"]["resolves file and invocation-buffer symbols"] = function()
    local path = vim.fs.joinpath(root, "lua", "agent.lua")
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].filetype = "lua"
    invocation_buf = bufnr

    local refs = resolve("@lua/agent.lua#M.send @#M.send", nil)
    MiniTest.expect.equality({ refs[1].state, refs[2].state }, { "resolved", "resolved" })
    MiniTest.expect.equality(refs[1].context.text, "function M.send(value)\n    return value\nend")
end

T["context resolver"]["invalidates the symbol cache after a buffer change"] = function()
    local path = vim.fs.joinpath(root, "lua", "agent.lua")
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].filetype = "lua"

    local context = require("aru.agent.context")
    local source = { bufnr = bufnr, path = path, filetype = "lua", line_count = 7 }
    MiniTest.expect.equality(context.symbols(source)[1].name, "M.send")
    vim.api.nvim_buf_set_lines(bufnr, 2, 5, false, { "function M.changed() end" })
    MiniTest.expect.equality(context.symbols(source)[1].name, "M.changed")
end

T["context resolver"]["deduplicates exact source ranges only"] = function()
    local context = require("aru.agent.context")
    local path = vim.fs.joinpath(root, "lua", "agent.lua")
    local items = context.compose({
        { kind = "block", source = true, path = path, start_line = 1, end_line = 2, text = "a" },
        { kind = "file", source = true, path = path, start_line = 1, end_line = 2, text = "a" },
        { kind = "file", source = true, path = path, start_line = 1, end_line = 3, text = "b" },
        {
            kind = "file",
            source = true,
            path = path,
            start_line = 1,
            end_line = 3,
            whole_file = true,
            text = "b",
        },
    })
    MiniTest.expect.equality(#items, 3)
end

T["payload"] = MiniTest.new_set()

T["payload"]["renders Pi file blocks before the unchanged prompt"] = function()
    local rendered = require("aru.agent.payload").render({
        context = {
            {
                kind = "file",
                source = true,
                path = '/tmp/a&"b.lua',
                symbol = 'M."send',
                start_line = 2,
                end_line = 4,
                text = "source",
            },
        },
        prompt = "  compare @a  ",
    })

    MiniTest.expect.equality(
        rendered,
        table.concat({
            '<file name="/tmp/a&amp;&quot;b.lua" symbol="M.&quot;send" lines="2-4">',
            "source",
            "</file>",
            "",
            "  compare @a  ",
        }, "\n")
    )
end

T["payload"]["omits line metadata for whole files"] = function()
    local rendered = require("aru.agent.payload").render({
        context = {
            {
                kind = "file",
                source = true,
                path = "/tmp/a.lua",
                start_line = 1,
                end_line = 10,
                whole_file = true,
                text = "source",
            },
        },
        prompt = "read",
    })
    MiniTest.expect.equality(rendered:find("lines=", 1, true), nil)
end

T["prompt integration"] = MiniTest.new_set()

local function invoke_insert_mapping(buf, lhs)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "i")) do
        if mapping.lhs == lhs then
            mapping.callback()
            return
        end
    end
    error("Missing prompt mapping " .. lhs)
end

local function open_prompt(send)
    local path = vim.fs.joinpath(root, "lua", "agent.lua")
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    invocation_buf = vim.api.nvim_get_current_buf()
    vim.bo[invocation_buf].filetype = "lua"
    require("aru.agent.prompt").open({
        cwd = root,
        invocation = {
            cwd = root,
            bufnr = invocation_buf,
            path = path,
            filetype = "lua",
            winid = vim.api.nvim_get_current_win(),
            mode = "n",
            cursor = { 1, 0 },
            selection = nil,
        },
        collect = {},
        send = send,
    })
    return vim.api.nvim_get_current_buf()
end

T["prompt integration"]["refuses unresolved submission without closing the prompt"] = function()
    local sent = false
    local prompt_buf = open_prompt(function()
        sent = true
        return true
    end)
    local text = "read @missing.lua"
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { text })
    vim.api.nvim_win_set_cursor(0, { 1, #text })

    local notification
    local notify = vim.notify
    vim.notify = function(message) notification = message end
    invoke_insert_mapping(prompt_buf, "<CR>")
    vim.notify = notify

    MiniTest.expect.equality(sent, false)
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(prompt_buf), true)
    MiniTest.expect.equality(notification, "Cannot submit unresolved reference @missing.lua")
    invoke_insert_mapping(prompt_buf, "<Esc>")
end

T["prompt integration"]["submission re-resolves changed buffer contents"] = function()
    local request
    local prompt_buf = open_prompt(function(value)
        request = value
        return true
    end)
    local text = "read @lua/agent.lua:3-3"
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { text })
    vim.api.nvim_win_set_cursor(0, { 1, #text })
    vim.api.nvim_buf_set_lines(invocation_buf, 2, 3, false, { "function M.changed(value)" })

    invoke_insert_mapping(prompt_buf, "<CR>")

    MiniTest.expect.equality(request.context[1].text, "function M.changed(value)")
    MiniTest.expect.equality(request.prompt, text)
end

T["prompt integration"]["exact preview warns and returns to the existing prompt"] = function()
    local prompt_buf = open_prompt(function() return true end)
    local text = "read @missing.lua"
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { text })
    vim.api.nvim_win_set_cursor(0, { 1, #text })

    invoke_insert_mapping(prompt_buf, "<C-X>")
    MiniTest.expect.equality(vim.api.nvim_get_current_buf() ~= prompt_buf, true)
    MiniTest.expect.equality(
        vim.api.nvim_buf_get_lines(0, 0, 1, false)[1],
        "NOT PART OF PAYLOAD — unresolved inline references:"
    )
    vim.api.nvim_win_close(0, true)
    vim.wait(50)
    MiniTest.expect.equality(vim.api.nvim_get_current_buf(), prompt_buf)
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false), { text })
    invoke_insert_mapping(prompt_buf, "<Esc>")
end

return T
