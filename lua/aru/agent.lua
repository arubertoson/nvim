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
---@field session aru.agent.runtime.SessionPolicy|nil
---@field collect aru.agent.collect.Type[]
---@field prompt string|nil
---@field preset string|nil

---@class aru.agent.ConfigState
---@field config aru.agent.config.Opts
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

local M = {}

local log = require("aru.log"):bind("agent")

local config = require("aru.agent.config")
local payload = require("aru.agent.payload")
local collect = require("aru.agent.collect")
local runtime = require("aru.agent.runtime")
local process = require("aru.agent.process")
local channels = require("aru.agent.channels")
local prompt_ui = require("aru.agent.prompt")
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

    local start_row = start_pos[2] - 1
    local end_row = end_pos[2] - 1
    local start_col = math.max(0, start_pos[3] - 1)
    local end_col = end_pos[3]

    if visual_mode == "V" then
        start_col = 0
        local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""
        end_col = #end_line
    end

    return {
        mode = visual_mode,
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
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
---@return aru.agent.runtime.SessionPolicy|nil
local function resolve_session_policy(request)
    if request.destination == channels.DESTINATION.EDITOR then return runtime.SESSION.NONE end
    if request.destination == channels.DESTINATION.FLOAT then
        return request.session or runtime.SESSION.NEW
    end
    return nil
end

---@param request aru.agent.Request
---@param state aru.agent.InvocationState
---@return boolean
local function send(request, state)
    local cfg = config.get()
    local session_policy = resolve_session_policy(request)

    ---@type aru.agent.ConfigState
    local ctx = { config = cfg, state = state }

    local items = {}
    if request.collect and #request.collect > 0 then
        items = collect.resolve(ctx, request.collect)
    end

    local message = payload.render({
        prompt = request.prompt,
        context = items,
    })

    ---@type aru.agent.channels.Transport
    local transport = {
        message = message,
        label = vim.fn.fnamemodify(cfg.executable, ":t"),
        cwd = state.cwd,
        run = function(stdin, on_event, on_exit)
            pcall(vim.fn.mkdir, cfg.session_dir, "p")
            local cmd = runtime.command(ctx, request, session_policy)
            process.json({
                executable = cmd[1],
                args = vim.list_slice(cmd, 2),
                stdin = stdin,
                cwd = state.cwd,
                on_event = on_event,
                on_exit = function(result)
                    if result.code == 0 then session.mark_success(session_policy, state.cwd) end
                    on_exit(result)
                end,
            })
        end,
    }

    local channel = channels.get(request.destination)
    if not channel then
        log:error("channel doesn't exist: %s", request.destination)
        return false
    end

    return channel.send(transport, ctx)
end

---@param request aru.agent.Request
---@return boolean
function M.send(request) return send(request, capture_invocation_state()) end

---@param opts aru.agent.PromptOpts|nil
function M.prompt(opts)
    local state = capture_invocation_state(opts and opts.visual_mode)
    return prompt_ui.open({
        send = function(request) return send(request, state) end,
    })
end

M.float = {}

---@param direction "down"|"up"
function M.float.scroll(direction) return require("aru.agent.channels.float").scroll(direction) end

function M.float.page_prev() return require("aru.agent.channels.float").page_prev() end

function M.float.page_next() return require("aru.agent.channels.float").page_next() end

function M.float.focus() return require("aru.agent.channels.float").focus() end

function M.float.close() return require("aru.agent.channels.float").close() end

---@param opts aru.agent.config.Opts|nil
function M.setup(opts) config.setup(opts) end

return M
