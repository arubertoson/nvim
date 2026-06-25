---@module "aru.agent.util"
---Shared helpers for agent modules.

local M = {}

---Trims leading and trailing whitespace from a string-like value.
---@param s string|nil
---@return string
function M.trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

---Returns the first line of text after trimming surrounding whitespace.
---@param s string|nil
---@return string
function M.first_line(s) return M.trim((s or ""):match("[^\n]*") or "") end

---Returns a short stderr summary for a completed system result.
---@param result vim.SystemCompleted
---@return string
function M.stderr_summary(result) return M.first_line(result.stderr) end

return M
