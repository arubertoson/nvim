---@module "aru.cmp.files"
---Blink source for fuzzy project-file references in agent prompts.

local M = {}

local CACHE_TTL_MS = 5000
local REFERENCE_MARKERS = { ["@"] = true, ["`"] = true }

---@class aru.cmp.files.Opts
---@field get_cwd fun(context: blink.cmp.Context): string
---@field max_results integer|nil
---@field cache_ttl_ms integer|nil

---@class aru.cmp.files.Request
---@field callback fun(files: string[]|nil)
---@field cancelled boolean

---@class aru.cmp.files.CacheEntry
---@field files string[]|nil
---@field expires_at integer|nil
---@field pending aru.cmp.files.Request[]|nil

---@class aru.cmp.files.Source
---@field opts aru.cmp.files.Opts
---@field cache table<string, aru.cmp.files.CacheEntry>
local Source = {}
Source.__index = Source

---@param line string
---@param cursor_col integer
---@return { start_col: integer, query: string }|nil
local function reference_at_cursor(line, cursor_col)
    local before_cursor = line:sub(1, cursor_col)
    local token_start = before_cursor:find("%S+$")
    if not token_start then return nil end

    local token = before_cursor:sub(token_start)
    if not REFERENCE_MARKERS[token:sub(1, 1)] then return nil end

    return {
        start_col = token_start,
        query = token:sub(2),
    }
end

---@param output string
---@return string[]
local function parse_files(output)
    local files = {}
    local start = 1

    while true do
        local separator = output:find("\0", start, true)
        if not separator then break end

        local path = output:sub(start, separator - 1)
        if path ~= "" then files[#files + 1] = path:gsub("^%./", "") end
        start = separator + 1
    end

    return files
end

---@param self aru.cmp.files.Source
---@param cwd string
---@param callback fun(files: string[]|nil)
---@return fun()|nil
local function load_files(self, cwd, callback)
    local now = vim.uv.now()
    local entry = self.cache[cwd]
    if entry and entry.files and entry.expires_at > now then
        callback(entry.files)
        return nil
    end

    local request = { callback = callback, cancelled = false }
    if entry and entry.pending then
        entry.pending[#entry.pending + 1] = request
        return function() request.cancelled = true end
    end

    entry = entry or {}
    entry.pending = { request }
    self.cache[cwd] = entry

    vim.system({ "fd", "--type", "f", "--hidden", "--exclude", ".git", "--print0", "." }, {
        cwd = cwd,
        text = true,
    }, function(result)
        vim.schedule(function()
            local pending = entry.pending
            entry.pending = nil

            local files
            if result.code == 0 then
                files = parse_files(result.stdout)
                entry.files = files
                entry.expires_at = vim.uv.now() + (self.opts.cache_ttl_ms or CACHE_TTL_MS)
            else
                self.cache[cwd] = nil
                vim.notify_once(
                    ("Agent file completion failed: %s"):format(vim.trim(result.stderr)),
                    vim.log.levels.ERROR
                )
            end

            for _, pending_request in ipairs(pending) do
                if not pending_request.cancelled then pending_request.callback(files) end
            end
        end)
    end)

    return function() request.cancelled = true end
end

---@param files string[]
---@param reference { start_col: integer, query: string }
---@param context blink.cmp.Context
---@param cwd string
---@param max_results integer
---@return lsp.CompletionItem[]
local function completion_items(files, reference, context, cwd, max_results)
    local matches = reference.query == "" and files or vim.fn.matchfuzzy(files, reference.query)
    local items = {}
    local range = {
        start = { line = context.cursor[1] - 1, character = reference.start_col },
        ["end"] = { line = context.cursor[1] - 1, character = context.cursor[2] },
    }
    local kind = require("blink.cmp.types").CompletionItemKind.File

    for index, path in ipairs(matches) do
        if index > max_results then break end
        items[#items + 1] = {
            label = path,
            kind = kind,
            filterText = reference.query ~= "" and reference.query or path,
            sortText = ("%06d"):format(index),
            textEdit = { newText = path, range = range },
            data = { path = path, full_path = vim.fs.joinpath(cwd, path) },
        }
    end
    return items
end

---@param opts aru.cmp.files.Opts
---@return aru.cmp.files.Source
function M.new(opts)
    vim.validate("aru.cmp.files.get_cwd", opts.get_cwd, "function")
    vim.validate("aru.cmp.files.max_results", opts.max_results, "number", true)
    vim.validate("aru.cmp.files.cache_ttl_ms", opts.cache_ttl_ms, "number", true)

    return setmetatable({ opts = opts, cache = {} }, Source)
end

function Source:get_trigger_characters() return { "@", "`", "/", ".", "\\" } end

---@param context blink.cmp.Context
---@param callback fun(response: blink.cmp.CompletionResponse)
---@return fun()|nil
function Source:get_completions(context, callback)
    local reference = reference_at_cursor(context.line, context.cursor[2])
    if not reference then
        callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
        return nil
    end

    local cwd = self.opts.get_cwd(context)
    return load_files(
        self,
        cwd,
        function(files)
            callback({
                items = files and completion_items(
                    files,
                    reference,
                    context,
                    cwd,
                    self.opts.max_results or 200
                ) or {},
                is_incomplete_forward = true,
                is_incomplete_backward = true,
            })
        end
    )
end

return M
