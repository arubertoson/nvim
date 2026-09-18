---@module "aru.cmp.buffer"
---Blink buffer source adapter for marker-prefixed agent references.

local M = {}

---@param line string
---@param cursor_col integer
---@return boolean
local function is_buffer_reference(line, cursor_col)
    local before_cursor = line:sub(1, cursor_col)
    local token_start = before_cursor:find("%S+$")
    return token_start ~= nil and before_cursor:sub(token_start, token_start) == "#"
end

function M.new(opts)
    local source = require("blink.cmp.sources.buffer").new(opts)
    local get_completions = source.get_completions

    function source:get_trigger_characters() return { "#" } end

    source.get_completions = function(self, context, callback)
        if not is_buffer_reference(context.line, context.cursor[2]) then
            callback({
                items = {},
                is_incomplete_forward = false,
                is_incomplete_backward = false,
            })
            return
        end

        return get_completions(self, context, callback)
    end

    return source
end

return M
