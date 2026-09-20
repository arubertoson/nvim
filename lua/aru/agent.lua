---@module "aru.agent"
---Coordinates Neovim-to-agent handoffs for editor context, tmux delivery,
---read floats, code generation, and the prompt UI. This module is
---the public facade; destination-specific UI state lives under `aru.agent.*`.
---
---Example:
---```lua
---local agent = require("aru.agent")
---local channels = require("aru.agent.channels")
---local collect = require("aru.agent.collect")
---agent.setup({ executable = "pi-dev", runtime = "pi", target_window_name = "agent" })
---agent.send({
---  destination = channels.DESTINATION.FLOAT,
---  collect = { collect.COLLECT.BLOCK },
---  prompt = "Explain this code",
---})
---```

---@class aru.agent.Request
---@field destination aru.agent.channels.Destination
---@field force_new_session boolean|nil
---@field collect aru.agent.collect.Type[]|nil
---@field prompt string|nil
---@field preset string|nil
---@field context aru.agent.payload.ContextItem[]|nil

---@class aru.agent.ConfigState
---@field config aru.agent.config.Config
---@field state aru.agent.InvocationState

---@class aru.agent.Selection
---@field mode string
---@field start_row integer 0-based
---@field start_col integer 0-based, inclusive
---@field end_row integer 0-based
---@field end_col integer 0-based, exclusive

---@class aru.agent.InvocationState
---@field cwd string
---@field bufnr integer
---@field path string
---@field filetype string
---@field winid integer
---@field mode string
---@field cursor [integer, integer]
---@field selection aru.agent.Selection|nil

---@class aru.agent.PromptOpts
---@field visual_mode string|nil
---@field collect aru.agent.collect.Type[]|nil

local M = {}

local log = require("aru.log")

local config = require("aru.agent.config")
local payload = require("aru.agent.payload")
local collect = require("aru.agent.collect")
local runtime = require("aru.agent.runtime")
local process = require("aru.agent.process")
local channels = require("aru.agent.channels")
local prompt_ui = require("aru.agent.prompt")
local request_validation = require("aru.agent.request")
local session = require("aru.agent.session")

---@param bufnr integer
---@param visual_mode string|nil
---@return aru.agent.Selection|nil
local function capture_selection(bufnr, visual_mode)
    if not visual_mode then return nil end

    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    if start_pos[2] == 0 or end_pos[2] == 0 then return nil end
    if start_pos[1] ~= 0 and start_pos[1] ~= bufnr then return nil end
    if end_pos[1] ~= 0 and end_pos[1] ~= bufnr then return nil end

    local segments = vim.fn.getregionpos(start_pos, end_pos, {
        type = visual_mode,
        eol = true,
    })
    if #segments == 0 then return nil end

    local first = segments[1][1]
    local last = segments[#segments][2]
    local end_row = last[2] - 1
    local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""

    return {
        mode = visual_mode,
        start_row = first[2] - 1,
        start_col = math.max(0, first[3] - 1),
        end_row = end_row,
        end_col = math.min(#end_line, math.max(0, last[3])),
    }
end

---@param visual_mode string|nil
---@return aru.agent.InvocationState
local function capture_invocation_state(visual_mode)
    local bufnr = vim.api.nvim_get_current_buf()
    local winid = vim.api.nvim_get_current_win()

    return {
        cwd = vim.fn.getcwd(),
        bufnr = bufnr,
        path = vim.api.nvim_buf_get_name(bufnr),
        filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr }),
        winid = winid,
        mode = visual_mode or vim.api.nvim_get_mode().mode,
        cursor = vim.api.nvim_win_get_cursor(winid),
        selection = capture_selection(bufnr, visual_mode),
    }
end

---@param request aru.agent.Request
---@param state aru.agent.InvocationState
---@return boolean
local function send(request, state)
    request_validation.validate(request)
    if request.destination == channels.DESTINATION.FLOAT and session.is_streaming() then
        vim.notify("An agent response is already streaming", vim.log.levels.WARN)
        return false
    end

    local cfg = config.get()
    ---@type aru.agent.ConfigState
    local ctx = { config = cfg, state = state }

    local channel = channels.get(request.destination)
    if not channel then
        log.error("Channel does not exist", request.destination)
        return false
    end

    local items = request.context or {}
    if not request.context and request.collect and #request.collect > 0 then
        items = collect.resolve(ctx, request.collect)
    end

    local message = payload.render({
        prompt = request.prompt,
        context = items,
    })
    local label = vim.fn.fnamemodify(cfg.executable, ":t")
    local response
    local run = function(_, _, _) error("Tmux transports do not run a local process") end

    if request.destination == channels.DESTINATION.FLOAT then
        runtime.assert_explicit_session(ctx)
        local agent_session
        agent_session, response =
            session.begin_read(state.cwd, label, request.force_new_session == true)
        local cmd = runtime.command(ctx, request, { kind = "explicit", id = agent_session.id })
        run = function(stdin, on_event, on_exit)
            vim.fs.mkdir(cfg.session_dir, { parents = true })
            process.json({
                executable = cmd[1],
                args = vim.list_slice(cmd, 2),
                stdin = stdin,
                cwd = state.cwd,
                on_event = on_event,
                on_exit = on_exit,
            })
        end
    elseif request.destination == channels.DESTINATION.EDITOR then
        local cmd = runtime.command(ctx, request, { kind = "none" })
        run = function(stdin, on_event, on_exit)
            return process.json({
                executable = cmd[1],
                args = vim.list_slice(cmd, 2),
                stdin = stdin,
                cwd = state.cwd,
                on_event = on_event,
                on_exit = on_exit,
            })
        end
    end

    ---@type aru.agent.channels.Transport
    local transport = {
        message = message,
        label = label,
        cwd = state.cwd,
        response = response,
        run = run,
    }

    return channel.send(transport, ctx)
end

---@param request aru.agent.Request
---@return boolean
function M.send(request) return send(request, capture_invocation_state()) end

---@param opts aru.agent.PromptOpts|nil
function M.prompt(opts)
    local visual_mode = opts and opts.visual_mode
    if visual_mode == "\22" then
        vim.notify("Agent prompts do not support blockwise selections", vim.log.levels.ERROR)
        return false
    end

    local state = capture_invocation_state(visual_mode)
    return prompt_ui.open({
        send = function(request) return send(request, state) end,
        collect = opts and opts.collect,
        cwd = state.cwd,
        invocation = state,
    })
end

M.float = {}

---@param direction "down"|"up"
function M.float.scroll(direction) return require("aru.agent.channels.float").scroll(direction) end

local function navigate_response(delta)
    if session.navigate_response(delta) then
        require("aru.agent.channels.float").show_selected()
    end
end

local function navigate_session(delta)
    if session.navigate_session(delta) then require("aru.agent.channels.float").show_selected() end
end

function M.float.response_prev() navigate_response(-1) end

function M.float.response_next() navigate_response(1) end

function M.float.session_prev() navigate_session(-1) end

function M.float.session_next() navigate_session(1) end

function M.float.focus() return require("aru.agent.channels.float").focus() end

function M.float.close() return require("aru.agent.channels.float").close() end

---@return boolean
function M.sessions_clear()
    if session.is_streaming() then
        vim.notify(
            "Cannot clear agent sessions while a response is streaming",
            vim.log.levels.ERROR
        )
        return false
    end

    local session_count, response_count = session.counts()
    local session_dir = config.get().session_dir
    local store_exists = vim.uv.fs_stat(session_dir) ~= nil
    local ok, err = pcall(vim.fs.rm, session_dir, { recursive = true })
    if not ok and not tostring(err):find("ENOENT", 1, true) then
        vim.notify("Failed to clear agent sessions: " .. tostring(err), vim.log.levels.ERROR)
        return false
    end

    require("aru.agent.channels.float").close()
    session.clear()

    if session_count == 0 and response_count == 0 and not store_exists then
        vim.notify("Agent sessions already empty", vim.log.levels.INFO)
    else
        vim.notify(
            ("Cleared %d agent sessions and %d responses"):format(session_count, response_count),
            vim.log.levels.INFO
        )
    end
    return true
end

---@param opts aru.agent.config.Opts|nil
function M.setup(opts)
    config.setup(opts)
    vim.api.nvim_create_user_command("AgentSessionsClear", M.sessions_clear, {
        desc = "Clear agent sessions and responses",
        force = true,
    })
end

return M
