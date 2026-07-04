---@module "aru.agent.process"
---Runs the agent runtime in JSON print mode and emits decoded stream events.

local M = {}

local log = require("aru.log"):bind("agent")

---@class aru.agent.process.RunOpts
---@field executable string
---@field args string[]|nil
---@field stdin string
---@field cwd string|nil
---@field on_event fun(event: table): nil
---@field on_exit fun(result: vim.SystemCompleted): nil

---@param result vim.SystemCompleted
---@return string
function M.stderr_summary(result)
    local line = (result.stderr or ""):match("[^\n]*") or ""
    return line:gsub("^%s+", ""):gsub("%s+$", "")
end

---@param opts aru.agent.process.RunOpts
---@return vim.SystemObj
function M.json(opts)
    local function handle_line(line)
        if line == "" then return end
        local ok, event = pcall(vim.json.decode, line)
        if ok and type(event) == "table" then
            vim.schedule(function() opts.on_event(event) end)
        else
            log:debug("invalid JSON stream line: %s", line)
        end
    end

    local leftover = ""
    local cmd = { opts.executable }
    vim.list_extend(cmd, opts.args or {})

    return vim.system(cmd, {
        text = true,
        stdin = opts.stdin,
        cwd = opts.cwd,
        stdout = function(err, data)
            if err then
                log:error("JSON stream stdout error: %s", err)
                return
            end
            if not data then return end
            local chunk = leftover .. data
            local parts = vim.split(chunk, "\n", { plain = true })
            leftover = parts[#parts]
            for i = 1, #parts - 1 do
                handle_line(parts[i])
            end
        end,
    }, function(result)
        if leftover ~= "" then
            handle_line(leftover)
            leftover = ""
        end
        vim.schedule(function() opts.on_exit(result) end)
    end)
end

return M
