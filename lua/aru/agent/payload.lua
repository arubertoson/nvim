---@module "aru.agent.payload"
local M = {}

---@class aru.agent.payload.ContextItem
---@field kind string
---@field path string|nil
---@field filetype string|nil
---@field start_line integer|nil
---@field end_line integer|nil
---@field text string

---@class aru.agent.payload.Payload
---@field prompt string|nil
---@field context aru.agent.payload.ContextItem[]

---@param payload aru.agent.payload.Payload
---@return string
function M.render(payload)
    local out = {}

    if payload.prompt and payload.prompt ~= "" then
        table.insert(out, payload.prompt)
        table.insert(out, "")
    end

    for _, item in ipairs(payload.context) do
        local label = item.kind
        if item.path and item.path ~= "" then
            label = ('<%s file="%s"'):format(item.kind, item.path)
        end

        if item.start_line and item.end_line then
            label = ('%s lines="%d-%d">'):format(label, item.start_line, item.end_line)
        end

        table.insert(out, label)
        table.insert(out, item.text)
        table.insert(out, ("</%s>"):format(item.kind))
    end

    local render = table.concat(out, "\n"):gsub("%s+$", "")
    return render
end

return M
