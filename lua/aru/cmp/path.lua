---@module "aru.cmp.path"
---Blink path source adapter for project-relative paths and agent references.

local M = {}

local function relative_path_start(line, cursor_col, reference_triggers)
    local before_cursor = line:sub(1, cursor_col)
    local token_start = before_cursor:find("%S+$")
    if not token_start then return nil end

    local token = before_cursor:sub(token_start)
    local marker = token:sub(1, 1)
    local path_start = token_start
    if reference_triggers and (marker == "@" or marker == "`") then
        path_start = path_start + 1
        token = token:sub(2)
    elseif not token:find("[/\\]") then
        return nil
    end

    if
        token:match("^%./")
        or token:match("^%.%./")
        or token:match("^~/")
        or token:match("^[/\\]")
        or token:match("^%$[%a_][%w_]*/")
        or token:match("^%a:[/\\]")
    then
        return nil
    end

    return path_start
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
    local reference_triggers = opts.reference_triggers == true
    opts.reference_triggers = nil

    local source = require("blink.cmp.sources.path").new(opts)
    local get_completions = source.get_completions
    local get_trigger_characters = source.get_trigger_characters

    source.get_trigger_characters = function(self)
        local triggers = get_trigger_characters(self)
        if reference_triggers then vim.list_extend(triggers, { "@", "`" }) end
        return triggers
    end

    source.get_completions = function(self, context, callback)
        local path_start = relative_path_start(context.line, context.cursor[2], reference_triggers)
        if not path_start then return get_completions(self, context, callback) end

        get_completions(
            self,
            shifted_context(context, path_start),
            function(response) callback(restore_text_edits(response)) end
        )
    end

    return source
end

return M
