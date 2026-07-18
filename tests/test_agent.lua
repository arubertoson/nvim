pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local function leave_visual_mode()
    local mode = vim.fn.mode()
    if mode == "v" or mode == "V" or mode == "\22" then
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "x",
            false
        )
    end
end

local function unload_agent()
    local float = package.loaded["aru.agent.channels.float"]
    if float then pcall(float.close) end

    local modules = {}
    for name in pairs(package.loaded) do
        if name == "aru.agent" or name:match("^aru%.agent%.") then modules[#modules + 1] = name end
    end
    for _, name in ipairs(modules) do
        package.loaded[name] = nil
    end
end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            leave_visual_mode()
            unload_agent()
            vim.cmd("silent! %bwipeout!")
            vim.cmd("enew!")
            vim.bo.swapfile = false
        end,
        post_case = function()
            leave_visual_mode()
            unload_agent()
            vim.cmd("silent! %bwipeout!")
        end,
    },
})

local function current_invocation(selection)
    local buf = vim.api.nvim_get_current_buf()
    return {
        cwd = vim.fn.getcwd(),
        bufnr = buf,
        path = vim.api.nvim_buf_get_name(buf),
        filetype = vim.bo[buf].filetype,
        winid = vim.api.nvim_get_current_win(),
        mode = selection and selection.mode or "n",
        cursor = vim.api.nvim_win_get_cursor(0),
        selection = selection,
    }
end

local function completed_transport(message, answer)
    return {
        message = message,
        label = "test",
        run = function(_, on_event, on_exit)
            on_event({
                type = "message_update",
                assistantMessageEvent = {
                    type = "text_delta",
                    delta = answer,
                },
            })
            on_exit({ code = 0, stderr = "" })
        end,
    }
end

T["runtime"] = MiniTest.new_set()

T["runtime"]["executable and runtime profile are independent"] = function()
    local runtime = require("aru.agent.runtime")
    local channels = require("aru.agent.channels")
    local ctx = {
        config = {
            executable = "/tmp/pi-dev",
            runtime = "pi",
            session_dir = "/tmp/agent-sessions",
        },
    }

    local command = runtime.command(ctx, {
        destination = channels.DESTINATION.FLOAT,
    }, runtime.SESSION.CONTINUE)

    MiniTest.expect.equality(command, {
        "/tmp/pi-dev",
        "--mode",
        "json",
        "--session-dir",
        "/tmp/agent-sessions",
        "--continue",
    })
end

T["runtime"]["editor runs without a saved session"] = function()
    local runtime = require("aru.agent.runtime")
    local channels = require("aru.agent.channels")
    local ctx = {
        config = {
            executable = "pi-dev",
            runtime = "pi",
            session_dir = "/tmp/agent-sessions",
        },
    }

    local command = runtime.command(ctx, {
        destination = channels.DESTINATION.EDITOR,
    }, runtime.SESSION.NONE)

    MiniTest.expect.equality(command, {
        "pi-dev",
        "--mode",
        "json",
        "--no-session",
    })
end

T["runtime"]["setup calls compose"] = function()
    local config = require("aru.agent.config")
    local before_open = function() end

    config.setup({ executable = "custom-pi" })
    config.setup({ float = { before_open = before_open } })

    MiniTest.expect.equality(config.get().executable, "custom-pi")
    MiniTest.expect.equality(config.get().float.before_open, before_open)
end

T["context"] = MiniTest.new_set()

T["context"]["normal mode ignores stale visual marks"] = function()
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].filetype = "text"

    local source = {}
    for i = 1, 120 do
        source[i] = ("line %d"):format(i)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
    vim.fn.setpos("'<", { buf, 1, 1, 0 })
    vim.fn.setpos("'>", { buf, 1, 6, 0 })
    vim.api.nvim_win_set_cursor(0, { 100, 0 })

    local item = require("aru.agent.collect.block").collect(current_invocation(nil))

    MiniTest.expect.equality(item.start_line, 50)
    MiniTest.expect.equality(item.end_line, 120)
end

T["context"]["explicit visual selection is collected exactly"] = function()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before", "selected text", "after" })

    local selection = {
        mode = "v",
        start_row = 1,
        start_col = 0,
        end_row = 1,
        end_col = 13,
    }
    local item = require("aru.agent.collect.block").collect(current_invocation(selection))

    MiniTest.expect.equality(item.text, "selected text")
    MiniTest.expect.equality(item.start_line, 2)
    MiniTest.expect.equality(item.end_line, 2)
end

T["generate"] = MiniTest.new_set()

T["generate"]["normal mode inserts at the captured cursor"] = function()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local  = true" })
    vim.api.nvim_win_set_cursor(0, { 1, 6 })

    local ctx = { state = current_invocation(nil) }
    local transport = completed_transport("insert a name", "value")

    MiniTest.expect.equality(require("aru.agent.channels.editor").send(transport, ctx), true)
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
        "local value = true",
    })
    MiniTest.expect.equality(vim.fn.mode(), "v")
end

T["generate"]["visual mode replaces and selects the captured range"] = function()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local old = true" })

    local selection = {
        mode = "v",
        start_row = 0,
        start_col = 6,
        end_row = 0,
        end_col = 9,
    }
    local ctx = { state = current_invocation(selection) }
    local transport = completed_transport("replace it", "new")

    MiniTest.expect.equality(require("aru.agent.channels.editor").send(transport, ctx), true)
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
        "local new = true",
    })
    MiniTest.expect.equality(vim.fn.mode(), "v")

    leave_visual_mode()
    MiniTest.expect.equality(vim.fn.getpos("'<")[3], 7)
    MiniTest.expect.equality(vim.fn.getpos("'>")[3], 9)
end

T["generate"]["one-shot generation preserves read continuation"] = function()
    local runtime = require("aru.agent.runtime")
    local session = require("aru.agent.session")
    local cwd = vim.fn.getcwd()

    session.mark_success(runtime.SESSION.NEW, cwd)
    session.mark_success(runtime.SESSION.NONE, cwd)

    MiniTest.expect.equality(session.can_continue(), true)
end

T["float"] = MiniTest.new_set()

T["float"]["lifecycle hooks run once per visibility transition"] = function()
    local before_open = 0
    local after_close = 0
    require("aru.agent.config").setup({
        float = {
            before_open = function() before_open = before_open + 1 end,
            after_close = function() after_close = after_close + 1 end,
        },
    })

    local float = require("aru.agent.channels.float")
    local transport = {
        message = "question",
        label = "test",
        run = function() end,
    }

    float.send(transport, {})
    float.send(transport, {})
    MiniTest.expect.equality({ before_open, after_close }, { 1, 0 })

    float.close()
    MiniTest.expect.equality({ before_open, after_close }, { 1, 1 })

    float.restore()
    float.focus()
    vim.api.nvim_win_close(0, true)
    MiniTest.expect.equality({ before_open, after_close }, { 2, 2 })
end

T["tmux"] = MiniTest.new_set()

T["tmux"]["handoff does not resolve a process runtime"] = function()
    local channels = require("aru.agent.channels")
    local captured
    channels.get = function()
        return {
            send = function(transport)
                captured = transport.message
                return true
            end,
        }
    end

    local agent = require("aru.agent")
    agent.setup({ runtime = "unsupported" })
    local sent = agent.send({
        destination = channels.DESTINATION.TMUX,
        collect = {},
        prompt = "handoff",
    })

    MiniTest.expect.equality(sent, true)
    MiniTest.expect.equality(captured, "handoff")
end

return T
