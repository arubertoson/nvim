---@module "aru.agent"
---Coordinates Neovim-to-agent handoffs for editor context, tmux delivery,
---scratch runs, read floats, code generation, and the prompt UI. This module is
---the public facade; destination-specific UI state lives under `aru.agent.*`.
---
---Example:
---```lua
---local agent = require("aru.agent")
---local channels = require("aru.agent.channels")
---local collect = require("aru.agent.collect")
---agent.setup({ executable = "pi-dev", target_window_name = "agent" })
---agent.send({
---  destination = channels.DESTINATION.FLOAT,
---  collect = { collect.COLLECT.BLOCK },
---  prompt = "Explain this code",
---})
---```

---@class aru.agent.Request
---@field destination aru.agent.channels.Destination
---@field mode aru.agent.runtime.Mode|nil
---@field collect aru.agent.collect.Type[]
---@field prompt string|nil
---@field preset string|nil

---@class aru.agent.ConfigState
---@field config aru.agent.config.Opts
---@field state aru.agent.InvocationState

---@class aru.agent.InvocationState
---@field cwd string
---@field bufnr integer
---@field path string
---@field filetype string
---@field winid integer
---@field mode string
---@field cursor [integer, integer]

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

---@return aru.agent.InvocationState
local function capture_invocation_state()
    local bufnr = vim.api.nvim_get_current_buf()
    local winid = vim.api.nvim_get_current_win()

    return {
        cwd = vim.fn.getcwd(),
        bufnr = bufnr,
        path = vim.api.nvim_buf_get_name(bufnr),
        filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr }),
        winid = winid,
        mode = vim.api.nvim_get_mode().mode,
        cursor = vim.api.nvim_win_get_cursor(winid),
    }
end

---@param request aru.agent.Request
---@return boolean
function M.send(request)
    local cfg = config.get()
    local state = capture_invocation_state()

    if not request.mode then request.mode = runtime.MODE.NEW_SESSION end

    pcall(vim.fn.mkdir, cfg.session_dir, "p")

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

    local cmd = runtime.command(ctx, request)
    local mode = request.mode

    ---@type aru.agent.channels.Transport
    local transport = {
        message = message,
        label = vim.fn.fnamemodify(cfg.executable, ":t"),
        cwd = state.cwd,
        run = function(stdin, on_event, on_exit)
            process.json({
                executable = cmd[1],
                args = vim.list_slice(cmd, 2),
                stdin = stdin,
                cwd = state.cwd,
                on_event = on_event,
                on_exit = function(result)
                    if result.code == 0 then session.mark_success(mode, state.cwd) end
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

---@return boolean
function M.can_continue() return session.can_continue() end

---@param opts aru.agent.prompt.OpenOpts|nil
function M.prompt(opts) return prompt_ui.open(opts, { send = M.send }) end

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
