---@module "aru.agent.stream"
---Runs the agent runtime in JSON print mode and emits decoded stream events.

local M = {}

local constants = require("aru.agent.constants")
local logger = require("aru.log"):bind("agent")

---@class AgentJsonStreamOpts
---@field executable string
---@field stdin string
---@field args string[]|nil
---@field on_event fun(event: table): nil
---@field on_exit fun(result: vim.SystemCompleted): nil

---Starts the runtime JSON stream.
---
---Stdout chunks may split JSON lines, so this keeps a leftover partial line and
---flushes it before `on_exit`. Event and exit callbacks are drained on the main
---loop, making it safe for callers to use Neovim APIs.
---@param opts AgentJsonStreamOpts
---@return vim.SystemObj
function M.run_json(opts)
    local leftover = ""
    local queue = {}
    local scheduled = false
    local finished = false
    local exit_sent = false
    local exit_result ---@type vim.SystemCompleted|nil

    local function enqueue_event(line)
        if line == "" then return end
        local ok, event = pcall(vim.json.decode, line)
        if ok and type(event) == "table" then
            table.insert(queue, event)
        else
            logger:debug("invalid JSON stream line: %s", line)
        end
    end

    local function drain()
        scheduled = false
        for i = 1, #queue do
            opts.on_event(queue[i])
        end
        queue = {}
        if finished and exit_result and not exit_sent then
            exit_sent = true
            opts.on_exit(exit_result)
        end
    end

    local function schedule_drain()
        if scheduled then return end
        scheduled = true
        vim.schedule(drain)
    end

    local cmd = { opts.executable }
    vim.list_extend(cmd, opts.args or constants.RUNTIME.JSON_ARGS)

    return vim.system(cmd, {
        text = true,
        stdin = opts.stdin,
        stdout = function(err, data)
            if err then
                logger:error("JSON stream stdout error: %s", err)
                return
            end
            if not data then return end
            local chunk = leftover .. data
            local parts = vim.split(chunk, "\n", { plain = true })
            leftover = parts[#parts]
            for i = 1, #parts - 1 do
                enqueue_event(parts[i])
            end
            schedule_drain()
        end,
    }, function(result)
        if leftover ~= "" then
            enqueue_event(leftover)
            leftover = ""
        end
        finished = true
        exit_result = result
        schedule_drain()
    end)
end

return M
