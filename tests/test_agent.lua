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

local function completed_float_transport(response, message, answer)
    local transport = completed_transport(message, answer)
    transport.response = response
    return transport
end

local function float_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative == "editor" and config.zindex == 49 then return win end
    end
    return nil
end

local function float_lines()
    local win = float_window()
    if not win then return nil end
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

local function text_event(delta)
    return {
        type = "message_update",
        assistantMessageEvent = {
            type = "text_delta",
            delta = delta,
        },
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
    }, {
        kind = "explicit",
        id = "session-123",
    })

    MiniTest.expect.equality(command, {
        "/tmp/pi-dev",
        "--mode",
        "json",
        "--session-dir",
        "/tmp/agent-sessions",
        "--session-id",
        "session-123",
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
    }, { kind = "none" })

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

T["runtime"]["runtime without explicit identity fails visibly"] = function()
    local constants = require("aru.agent.constants")
    local runtime = require("aru.agent.runtime")
    local channels = require("aru.agent.channels")
    constants.RUNTIME.incapable = {
        JSON_ARGS = { "--json" },
        NO_SESSION = "--no-session",
        PRESET = "--preset",
        SESSION_DIR = "--session-dir",
    }

    local ok, err = pcall(runtime.command, {
        config = {
            executable = "incapable",
            runtime = "incapable",
            session_dir = "/tmp/sessions",
        },
    }, {
        destination = channels.DESTINATION.FLOAT,
    }, {
        kind = "explicit",
        id = "id",
    })

    constants.RUNTIME.incapable = nil
    MiniTest.expect.equality(ok, false)
    MiniTest.expect.equality(tostring(err):find("explicit agent session", 1, true) ~= nil, true)
end

T["session"] = MiniTest.new_set()

T["session"]["new sessions have distinct explicit identities"] = function()
    local session = require("aru.agent.session")
    local first, first_response = session.begin_read("/project", "pi", false)
    session.finish(first_response, "complete")
    local second = session.begin_read("/project", "pi", true)

    local selected = session.selection()
    MiniTest.expect.equality(first.id ~= second.id, true)
    MiniTest.expect.equality(selected.session, second)
    MiniTest.expect.equality({ selected.session_index, selected.session_count }, { 2, 2 })
end

T["session"]["continue appends only to the selected matching session"] = function()
    local session = require("aru.agent.session")
    local first, first_response = session.begin_read("/project", "pi", false)
    session.finish(first_response, "complete")
    local continued, second_response = session.begin_read("/project", "pi", false)

    MiniTest.expect.equality(continued, first)
    MiniTest.expect.equality(#first.responses, 2)
    MiniTest.expect.equality(session.selection().response, second_response)
end

T["session"]["working directory mismatch creates a session"] = function()
    local session = require("aru.agent.session")
    local first, response = session.begin_read("/one", "pi", false)
    session.finish(response, "complete")
    local second = session.begin_read("/two", "pi", false)

    MiniTest.expect.equality(first ~= second, true)
    MiniTest.expect.equality(session.selection().session.cwd, "/two")
end

T["session"]["navigation stops at boundaries and restores response selection"] = function()
    local session = require("aru.agent.session")
    local first, response = session.begin_read("/one", "pi", false)
    session.finish(response, "complete")
    local _, second_response = session.begin_read("/one", "pi", false)
    session.finish(second_response, "complete")

    MiniTest.expect.equality(session.navigate_response(1), false)
    MiniTest.expect.equality(session.navigate_response(-1), true)
    MiniTest.expect.equality(session.navigate_response(-1), false)

    local second_session, third_response = session.begin_read("/one", "pi", true)
    session.finish(third_response, "complete")
    MiniTest.expect.equality(session.navigate_session(1), false)
    MiniTest.expect.equality(session.navigate_session(-1), true)
    MiniTest.expect.equality(session.selection().session, first)
    MiniTest.expect.equality(session.selection().response_index, 1)

    session.navigate_response(1)
    session.navigate_session(1)
    MiniTest.expect.equality(session.selection().session, second_session)
    session.navigate_session(-1)
    MiniTest.expect.equality(session.selection().response_index, 2)
    MiniTest.expect.equality(session.navigate_session(-1), false)
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

T["generate"]["progress uses a separate virtual line and highlights the target"] = function()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local old = true" })

    local selection = {
        mode = "v",
        start_row = 0,
        start_col = 6,
        end_row = 0,
        end_col = 9,
    }
    local finish
    local transport = {
        message = "replace it",
        label = "test",
        run = function(_, _, on_exit) finish = on_exit end,
    }

    require("aru.agent.channels.editor").send(transport, {
        state = current_invocation(selection),
    })

    local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
    MiniTest.expect.equality(#marks, 1)
    MiniTest.expect.equality(marks[1][4].virt_text, nil)
    MiniTest.expect.equality(marks[1][4].virt_lines ~= nil, true)
    MiniTest.expect.equality(marks[1][4].hl_group, "Visual")
    MiniTest.expect.equality({ marks[1][4].end_row, marks[1][4].end_col }, { 0, 9 })

    finish({ code = 0, stderr = "" })
    MiniTest.expect.equality(#vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {}), 0)
end

T["generate"]["one-shot generation preserves read session history"] = function()
    local session = require("aru.agent.session")
    local cwd = vim.fn.getcwd()
    local _, response = session.begin_read(cwd, "test", false)
    session.finish(response, "complete")

    local before = session.selection()
    local buf = vim.api.nvim_get_current_buf()
    local transport = completed_transport("insert a value", "generated")
    require("aru.agent.channels.editor").send(transport, {
        state = current_invocation(nil),
    })

    local after = session.selection()
    MiniTest.expect.equality(after.session.id, before.session.id)
    MiniTest.expect.equality(after.response, before.response)
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "generated" })
end

T["float"] = MiniTest.new_set()

T["float"]["side and width configure window geometry"] = function()
    local opened_layout
    require("aru.agent.config").setup({
        float = {
            side = "left",
            width = 72,
            before_open = function(layout) opened_layout = layout end,
        },
    })

    local session = require("aru.agent.session")
    local _, response = session.begin_read(vim.fn.getcwd(), "test", false)
    local float = require("aru.agent.channels.float")
    float.send({
        message = "question",
        label = "test",
        response = response,
        run = function() end,
    }, {})

    local float_config
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local win_config = vim.api.nvim_win_get_config(win)
        if win_config.relative == "editor" then
            float_config = win_config
            break
        end
    end

    MiniTest.expect.equality(opened_layout, { side = "left", width = 72 })
    MiniTest.expect.equality(float_config.width, 72)
    MiniTest.expect.equality(float_config.col, 3)
    float.close()
end

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
    local session = require("aru.agent.session")
    local _, first = session.begin_read(vim.fn.getcwd(), "test", false)
    float.send(completed_float_transport(first, "question", "first"), {})
    local _, second = session.begin_read(vim.fn.getcwd(), "test", false)
    float.send(completed_float_transport(second, "question", "second"), {})
    MiniTest.expect.equality({ before_open, after_close }, { 1, 0 })

    float.close()
    MiniTest.expect.equality({ before_open, after_close }, { 1, 1 })

    float.restore()
    float.focus()
    vim.api.nvim_win_close(0, true)
    MiniTest.expect.equality({ before_open, after_close }, { 2, 2 })
end

T["float"]["title always shows session and response indices"] = function()
    local session = require("aru.agent.session")
    local float = require("aru.agent.channels.float")
    local _, response = session.begin_read(vim.fn.getcwd(), "pi", false)
    local finish
    float.send({
        message = "question",
        label = "pi",
        response = response,
        run = function(_, _, on_exit) finish = on_exit end,
    }, {})

    local config = vim.api.nvim_win_get_config(float_window())
    MiniTest.expect.equality(
        config.title[1][1],
        " pi · S1/1 · R1/1 · ⠋ thinking about clouds "
    )

    finish({ code = 0, stderr = "" })
    config = vim.api.nvim_win_get_config(float_window())
    MiniTest.expect.equality(config.title[1][1], " pi · S1/1 · R1/1 ")
end

T["float"]["navigation does not interrupt a background stream"] = function()
    local session = require("aru.agent.session")
    local float = require("aru.agent.channels.float")
    local _, first = session.begin_read("/one", "pi", false)
    float.send(completed_float_transport(first, "first prompt", "first answer"), {})

    local _, second = session.begin_read("/two", "pi", true)
    float.send(completed_float_transport(second, "second prompt", "second answer"), {})

    local _, streaming = session.begin_read("/two", "pi", false)
    local on_event
    local on_exit
    float.send({
        message = "third prompt",
        label = "pi",
        response = streaming,
        run = function(_, event, exit)
            on_event = event
            on_exit = exit
        end,
    }, {})

    session.navigate_response(-1)
    float.show_selected()
    MiniTest.expect.equality(float_lines(), { "second answer" })
    MiniTest.expect.equality(
        vim.api.nvim_win_get_config(float_window()).title[1][1],
        " pi · S2/2 · R1/2 "
    )

    on_event(text_event("background output"))
    MiniTest.expect.equality(streaming.lines, { "background output" })
    MiniTest.expect.equality(float_lines(), { "second answer" })

    session.navigate_session(-1)
    float.show_selected()
    on_exit({ code = 0, stderr = "" })
    MiniTest.expect.equality(session.selection().session_index, 1)
    MiniTest.expect.equality(streaming.status, "complete")

    session.navigate_session(1)
    MiniTest.expect.equality(session.selection().response_index, 1)
    session.navigate_response(1)
    float.show_selected()
    MiniTest.expect.equality(float_lines(), { "background output" })
end

T["float"]["closing while streaming preserves output for restore"] = function()
    local session = require("aru.agent.session")
    local float = require("aru.agent.channels.float")
    local _, response = session.begin_read(vim.fn.getcwd(), "pi", false)
    local on_event
    local on_exit
    float.send({
        message = "question",
        label = "pi",
        response = response,
        run = function(_, event, exit)
            on_event = event
            on_exit = exit
        end,
    }, {})

    float.close()
    on_event(text_event("received while closed"))
    MiniTest.expect.equality(float_window(), nil)
    MiniTest.expect.equality(response.lines, { "received while closed" })

    float.restore()
    MiniTest.expect.equality(float_lines(), { "received while closed" })
    on_exit({ code = 0, stderr = "" })
end

T["float"]["failed responses remain visible without rendering the prompt"] = function()
    local session = require("aru.agent.session")
    local float = require("aru.agent.channels.float")
    local _, response = session.begin_read(vim.fn.getcwd(), "pi", false)
    float.send({
        message = "prompt must not be rendered",
        label = "pi",
        response = response,
        run = function(_, on_event, on_exit)
            on_event(text_event("partial"))
            on_exit({ code = 1, stderr = "failure details\nmore" })
        end,
    }, {})

    MiniTest.expect.equality(response.status, "error")
    MiniTest.expect.equality(float_lines(), { "partial", "[error: failure details]" })
end

T["facade"] = MiniTest.new_set()

T["facade"]["read requests reuse explicit identity unless forced new"] = function()
    local calls = {}
    require("aru.agent.process").json = function(opts)
        calls[#calls + 1] = opts
        opts.on_exit({ code = 0, stderr = "" })
    end

    local channels = require("aru.agent.channels")
    local agent = require("aru.agent")
    local session_dir = vim.fn.tempname()
    agent.setup({ session_dir = session_dir })

    agent.send({
        destination = channels.DESTINATION.FLOAT,
        collect = {},
        prompt = "first",
    })
    agent.send({
        destination = channels.DESTINATION.FLOAT,
        collect = {},
        prompt = "continue",
    })
    agent.send({
        destination = channels.DESTINATION.FLOAT,
        force_new_session = true,
        collect = {},
        prompt = "new",
    })

    local function session_id(call)
        for index, arg in ipairs(call.args) do
            if arg == "--session-id" then return call.args[index + 1] end
        end
    end

    MiniTest.expect.equality(session_id(calls[1]), session_id(calls[2]))
    MiniTest.expect.equality(session_id(calls[2]) ~= session_id(calls[3]), true)
    MiniTest.expect.equality(require("aru.agent.session").counts(), 2)
    pcall(vim.fs.rm, session_dir, { recursive = true })
end

T["facade"]["concurrent Read is rejected without starting a process"] = function()
    local calls = {}
    require("aru.agent.process").json = function(opts) calls[#calls + 1] = opts end

    local channels = require("aru.agent.channels")
    local agent = require("aru.agent")
    local session_dir = vim.fn.tempname()
    agent.setup({ session_dir = session_dir })

    local first = agent.send({
        destination = channels.DESTINATION.FLOAT,
        collect = {},
        prompt = "first",
    })
    local second = agent.send({
        destination = channels.DESTINATION.FLOAT,
        collect = {},
        prompt = "second",
    })

    MiniTest.expect.equality(first, true)
    MiniTest.expect.equality(second, false)
    MiniTest.expect.equality(#calls, 1)
    MiniTest.expect.equality(require("aru.agent.session").counts(), 1)
    pcall(vim.fs.rm, session_dir, { recursive = true })
end

T["facade"]["Generate does not create or select Agent Sessions"] = function()
    require("aru.agent.process").json = function(opts)
        opts.on_event(text_event("generated"))
        opts.on_exit({ code = 0, stderr = "" })
    end

    local channels = require("aru.agent.channels")
    local agent = require("aru.agent")
    local session_dir = vim.fn.tempname()
    agent.setup({ session_dir = session_dir })
    local sent = agent.send({
        destination = channels.DESTINATION.EDITOR,
        collect = {},
        prompt = "generate",
    })

    MiniTest.expect.equality(sent, true)
    MiniTest.expect.equality({ require("aru.agent.session").counts() }, { 0, 0 })
    MiniTest.expect.equality(vim.uv.fs_stat(session_dir), nil)
end

T["clear"] = MiniTest.new_set()

T["clear"]["removes disk and memory state and closes the float"] = function()
    local session_dir = vim.fn.tempname()
    vim.fs.mkdir(session_dir, { parents = true })
    vim.fn.writefile({ "session" }, session_dir .. "/session.json")

    local agent = require("aru.agent")
    agent.setup({ session_dir = session_dir })
    local session = require("aru.agent.session")
    local _, response = session.begin_read(vim.fn.getcwd(), "pi", false)
    require("aru.agent.channels.float").send(
        completed_float_transport(response, "question", "answer"),
        {}
    )

    local notification
    local notify = vim.notify
    vim.notify = function(message) notification = message end
    local ok, cleared = pcall(agent.sessions_clear)
    vim.notify = notify
    if not ok then error(cleared) end

    MiniTest.expect.equality(cleared, true)
    MiniTest.expect.equality(vim.uv.fs_stat(session_dir), nil)
    MiniTest.expect.equality({ session.counts() }, { 0, 0 })
    MiniTest.expect.equality(float_window(), nil)
    MiniTest.expect.equality(notification, "Cleared 1 agent sessions and 1 responses")
    MiniTest.expect.equality(vim.fn.exists(":AgentSessionsClear"), 2)
end

T["clear"]["an absent Session Store still clears memory"] = function()
    local session_dir = vim.fn.tempname()
    local agent = require("aru.agent")
    agent.setup({ session_dir = session_dir })
    local session = require("aru.agent.session")
    local _, response = session.begin_read(vim.fn.getcwd(), "pi", false)
    session.finish(response, "complete")

    local notification
    local notify = vim.notify
    vim.notify = function(message) notification = message end
    local ok, cleared = pcall(agent.sessions_clear)
    vim.notify = notify
    if not ok then error(cleared) end

    MiniTest.expect.equality(cleared, true)
    MiniTest.expect.equality({ session.counts() }, { 0, 0 })
    MiniTest.expect.equality(notification, "Cleared 1 agent sessions and 1 responses")
end

T["clear"]["already empty reports without error"] = function()
    local agent = require("aru.agent")
    agent.setup({ session_dir = vim.fn.tempname() })

    local notification
    local notify = vim.notify
    vim.notify = function(message) notification = message end
    local ok, cleared = pcall(agent.sessions_clear)
    vim.notify = notify
    if not ok then error(cleared) end

    MiniTest.expect.equality(cleared, true)
    MiniTest.expect.equality(notification, "Agent sessions already empty")
end

T["clear"]["disk failure preserves memory and float visibility"] = function()
    local session_dir = vim.fn.tempname()
    vim.fs.mkdir(session_dir, { parents = true })
    local agent = require("aru.agent")
    agent.setup({ session_dir = session_dir })
    local session = require("aru.agent.session")
    local _, response = session.begin_read(vim.fn.getcwd(), "pi", false)
    require("aru.agent.channels.float").send(
        completed_float_transport(response, "question", "answer"),
        {}
    )
    local win = float_window()

    local rm = vim.fs.rm
    vim.fs.rm = function() error("EACCES: denied") end
    local ok, cleared = pcall(agent.sessions_clear)
    vim.fs.rm = rm
    pcall(vim.fs.rm, session_dir, { recursive = true })
    if not ok then error(cleared) end

    MiniTest.expect.equality(cleared, false)
    MiniTest.expect.equality({ session.counts() }, { 1, 1 })
    MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), true)
end

T["clear"]["streaming refusal preserves all state"] = function()
    local session_dir = vim.fn.tempname()
    vim.fs.mkdir(session_dir, { parents = true })
    local agent = require("aru.agent")
    agent.setup({ session_dir = session_dir })
    local session = require("aru.agent.session")
    local _, response = session.begin_read(vim.fn.getcwd(), "pi", false)
    local finish
    require("aru.agent.channels.float").send({
        message = "question",
        label = "pi",
        response = response,
        run = function(_, _, on_exit) finish = on_exit end,
    }, {})
    local win = float_window()

    local removed = false
    local rm = vim.fs.rm
    vim.fs.rm = function()
        removed = true
        return rm(session_dir, { recursive = true })
    end
    local ok, cleared = pcall(agent.sessions_clear)
    vim.fs.rm = rm
    if not ok then error(cleared) end

    MiniTest.expect.equality(cleared, false)
    MiniTest.expect.equality(removed, false)
    MiniTest.expect.equality(response.status, "streaming")
    MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), true)
    finish({ code = 0, stderr = "" })
    pcall(vim.fs.rm, session_dir, { recursive = true })
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
    MiniTest.expect.equality({ require("aru.agent.session").counts() }, { 0, 0 })
end

return T
