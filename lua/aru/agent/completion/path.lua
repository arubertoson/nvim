---@module "aru.agent.completion.path"
---Blink source adapter for project-relative Inline Reference paths.

local M = {}

---@param line string
---@param cursor_col integer
local function reference_path_start(line, cursor_col)
    local ref = require("aru.agent.reference").at_cursor(line, cursor_col)
    if not ref or ref.selector or ref.invalid then return nil end
    if
        ref.path
        and (ref.path:sub(1, 1) == "/" or ref.path:match("^%a:[/\\]") or ref.path:match("^%.%.?/"))
    then
        return nil
    end
    return ref.span.start_col + 2 -- Lua index immediately after @
end

local function shifted_context(context, path_start)
    local rewritten = vim.tbl_extend("force", {}, context)
    rewritten.line = context.line:sub(1, path_start - 1) .. "./" .. context.line:sub(path_start)
    rewritten.cursor = { context.cursor[1], context.cursor[2] + 2 }
    rewritten.bounds = vim.tbl_extend("force", {}, context.bounds, {
        start_col = context.bounds.start_col + 2,
    })
    return rewritten
end

local function restore_text_edits(response)
    if not response or not response.items then return response end
    for _, item in ipairs(response.items) do
        local range = item.textEdit and item.textEdit.range
        if range then
            range = vim.deepcopy(range)
            range.start.character = range.start.character - 2
            range["end"].character = range["end"].character - 2
            item.textEdit.range = range
        end
    end
    return response
end

function M.new(opts)
    opts = vim.deepcopy(opts or {})
    local source = require("blink.cmp.sources.path").new(opts)
    local get_completions = source.get_completions
    local get_trigger_characters = source.get_trigger_characters

    source.get_trigger_characters = function(self)
        local triggers = get_trigger_characters(self)
        vim.list_extend(triggers, { "@" })
        return triggers
    end

    source.get_completions = function(self, completion_context, callback)
        local path_start =
            reference_path_start(completion_context.line, completion_context.cursor[2])
        if not path_start then
            callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
            return
        end
        get_completions(
            self,
            shifted_context(completion_context, path_start),
            function(response) callback(restore_text_edits(response)) end
        )
    end

    return source
end

return M
