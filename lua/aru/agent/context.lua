---@module "aru.agent.context"
---Resolves Inline References and composes their Context Items with invocation
---and collector context.

local M = {}

local reference_parser = require("aru.agent.reference")

---@class aru.agent.context.Symbol
---@field name string
---@field kind string
---@field start_line integer
---@field end_line integer
---@field node TSNode

---@class aru.agent.context.BuildResult
---@field references aru.agent.reference.Reference[]
---@field context aru.agent.payload.ContextItem[]
---@field blocking aru.agent.reference.Reference[]

---@class aru.agent.context.BuildOpts
---@field prompt string
---@field cursor [integer, integer]|nil
---@field cwd string
---@field invocation aru.agent.InvocationState
---@field collect aru.agent.collect.Type[]

---@class aru.agent.context.BufferSource
---@field bufnr integer
---@field path string
---@field filetype string
---@field line_count integer

---@type table<integer, { changedtick: integer, symbols: aru.agent.context.Symbol[] }>
local symbol_cache = {}

---@param path string
local function normalized(path) return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")) end

---@param path string
---@param cwd string
local function absolute_path(path, cwd)
    if path == "" then return nil end
    if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") then return normalized(path) end
    return normalized(vim.fs.joinpath(cwd, path))
end

---@param path string
---@return integer|nil
local function loaded_buffer(path)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name ~= "" and normalized(name) == path then return bufnr end
        end
    end
    return nil
end

---@param path string
---@return aru.agent.context.BufferSource|nil, string|nil
local function acquire_buffer(path)
    local bufnr = loaded_buffer(path)
    if not bufnr then
        local stat = vim.uv.fs_stat(path)
        if not stat then return nil, "file does not exist" end
        if stat.type ~= "file" then return nil, "path is not a file" end

        bufnr = vim.fn.bufadd(path)
        vim.fn.bufload(bufnr)
        if not vim.api.nvim_buf_is_loaded(bufnr) then
            error("Failed to load referenced file: " .. path)
        end
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
        error("Referenced buffer became invalid: " .. path)
    end

    return {
        bufnr = bufnr,
        path = path,
        filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr }),
        line_count = vim.api.nvim_buf_line_count(bufnr),
    },
        nil
end

---@param source aru.agent.context.BufferSource
---@param start_line integer
---@param end_line integer
local function source_text(source, start_line, end_line)
    return table.concat(
        vim.api.nvim_buf_get_lines(source.bufnr, start_line - 1, end_line, false),
        "\n"
    )
end

---@param node TSNode
local function node_kind(node)
    local node_type = node:type()
    if node_type:find("method", 1, true) then return "Method" end
    if node_type:find("class", 1, true) then return "Class" end
    if node_type:find("interface", 1, true) then return "Interface" end
    if node_type:find("struct", 1, true) then return "Struct" end
    if node_type:find("enum", 1, true) then return "Enum" end
    if node_type:find("function", 1, true) then return "Function" end
    return "Declaration"
end

---@param node TSNode
local function is_symbol_node(node)
    local node_type = node:type()
    if node_type:find("call", 1, true) or node_type:find("type", 1, true) then return false end
    return node_type:find("function", 1, true) ~= nil
        or node_type:find("method", 1, true) ~= nil
        or node_type:find("class", 1, true) ~= nil
        or node_type:find("interface", 1, true) ~= nil
        or node_type:find("struct", 1, true) ~= nil
        or node_type:find("enum", 1, true) ~= nil
        or node_type:find("declaration", 1, true) ~= nil
end

---@param node TSNode
---@param bufnr integer
local function symbol_name(node, bufnr)
    for _, field in ipairs({ "name", "declarator" }) do
        local named = node:field(field)[1]
        if named then
            local text = vim.treesitter.get_node_text(named, bufnr)
            if text and text ~= "" and not text:find("\n", 1, true) then return text end
        end
    end
    return nil
end

---@param node TSNode
local function node_lines(node)
    local start_row, _, end_row, end_col = node:range()
    local end_exclusive = end_row + (end_col > 0 and 1 or 0)
    return start_row + 1, end_exclusive
end

---@param source aru.agent.context.BufferSource
---@return aru.agent.context.Symbol[]
function M.symbols(source)
    local changedtick = vim.api.nvim_buf_get_changedtick(source.bufnr)
    local cached = symbol_cache[source.bufnr]
    if cached and cached.changedtick == changedtick then return cached.symbols end

    local lang = vim.treesitter.language.get_lang(source.filetype)
    if not lang then return {} end
    local ok_parser, parser = pcall(vim.treesitter.get_parser, source.bufnr, lang)
    if not ok_parser or not parser then return {} end
    local ok_parse, trees = pcall(parser.parse, parser)
    local root = ok_parse and trees and trees[1] and trees[1]:root() or nil
    if not root then return {} end

    local symbols = {}
    local seen = {}
    local function visit(node)
        if node:named() and is_symbol_node(node) then
            local name = symbol_name(node, source.bufnr)
            if name then
                local start_line, end_line = node_lines(node)
                local key = table.concat({ name, start_line, end_line }, "\0")
                if not seen[key] then
                    seen[key] = true
                    symbols[#symbols + 1] = {
                        name = name,
                        kind = node_kind(node),
                        start_line = start_line,
                        end_line = end_line,
                        node = node,
                    }
                end
            end
        end
        for child in node:iter_children() do
            if child:named() then visit(child) end
        end
    end
    visit(root)

    table.sort(symbols, function(left, right)
        if left.start_line == right.start_line then return left.name < right.name end
        return left.start_line < right.start_line
    end)
    symbol_cache[source.bufnr] = { changedtick = changedtick, symbols = symbols }
    return symbols
end

---@param ref aru.agent.reference.Reference
---@param cwd string
---@param invocation_buf integer
---@return aru.agent.context.BufferSource|nil, string|nil
local function reference_source(ref, cwd, invocation_buf)
    if not ref.path and ref.selector and ref.selector.kind == "symbol" then
        if not vim.api.nvim_buf_is_valid(invocation_buf) then
            return nil, "invocation buffer is no longer valid"
        end
        local path = vim.api.nvim_buf_get_name(invocation_buf)
        if path == "" then return nil, "invocation buffer has no file path" end
        return acquire_buffer(normalized(path))
    end

    local path = ref.path and absolute_path(ref.path, cwd) or nil
    if not path then return nil, "reference has no file path" end
    return acquire_buffer(path)
end

---@param ref aru.agent.reference.Reference
---@param cwd string
---@param invocation_buf integer
---@return aru.agent.payload.ContextItem|nil, string|nil, boolean
local function resolve_reference(ref, cwd, invocation_buf)
    if ref.invalid then return nil, ref.error or "invalid reference", false end
    if ref.incomplete then return nil, "incomplete reference", true end

    local source, source_error = reference_source(ref, cwd, invocation_buf)
    if not source then return nil, source_error, true end

    local selector = ref.selector
    if not selector then
        return {
            kind = "file",
            source = true,
            path = source.path,
            filetype = source.filetype,
            start_line = 1,
            end_line = source.line_count,
            whole_file = true,
            text = source_text(source, 1, source.line_count),
        },
            nil,
            false
    end

    if selector.kind == "lines" then
        local start_line = selector.start_line
        local end_line = selector.end_line
        if not start_line or not end_line then return nil, "incomplete line range", true end
        if start_line < 1 or end_line < 1 then
            return nil, "line numbers must be positive", false
        end
        if start_line > end_line then return nil, "line range is reversed", false end
        if end_line > source.line_count then
            return nil, "line range is outside the file", false
        end

        return {
            kind = "file",
            source = true,
            path = source.path,
            filetype = source.filetype,
            start_line = start_line,
            end_line = end_line,
            text = source_text(source, start_line, end_line),
        },
            nil,
            false
    end

    local matches = {}
    for _, symbol in ipairs(M.symbols(source)) do
        if symbol.name == selector.name then matches[#matches + 1] = symbol end
    end
    if #matches == 0 then return nil, "symbol does not exist", true end
    if #matches > 1 then return nil, "symbol is ambiguous", false end

    local symbol = matches[1]
    return {
        kind = "file",
        source = true,
        path = source.path,
        filetype = source.filetype,
        symbol = symbol.name,
        start_line = symbol.start_line,
        end_line = symbol.end_line,
        text = source_text(source, symbol.start_line, symbol.end_line),
    },
        nil,
        false
end

---@param text string
---@param cursor [integer, integer]|nil
---@param cwd string
---@param invocation_buf integer
---@return aru.agent.reference.Reference[]
function M.resolve(text, cursor, cwd, invocation_buf)
    local references = reference_parser.parse(text, cursor)
    for _, ref in ipairs(references) do
        local item, resolution_error, recoverable = resolve_reference(ref, cwd, invocation_buf)
        ref.context = item
        reference_parser.classify(ref, cursor, resolution_error, recoverable)
    end
    return references
end

---@param items aru.agent.payload.ContextItem[]
---@return aru.agent.payload.ContextItem[]
function M.compose(items)
    local composed = {}
    local seen = {}
    for _, item in ipairs(items) do
        local key
        if item.source and item.path then
            if item.whole_file then
                key = table.concat({ normalized(item.path), "whole" }, "\0")
            elseif item.start_line and item.end_line then
                key = table.concat({ normalized(item.path), item.start_line, item.end_line }, "\0")
            end
        end
        if not key or not seen[key] then
            if key then seen[key] = true end
            composed[#composed + 1] = item
        end
    end
    return composed
end

---@param opts aru.agent.context.BuildOpts
---@return aru.agent.context.BuildResult
function M.build(opts)
    local references = M.resolve(opts.prompt, opts.cursor, opts.cwd, opts.invocation.bufnr)
    local ordered_collectors = {}
    for _, name in ipairs(opts.collect) do
        if name == "block" then
            ordered_collectors[#ordered_collectors + 1] = name
            break
        end
    end
    for _, name in ipairs(opts.collect) do
        if name ~= "block" then ordered_collectors[#ordered_collectors + 1] = name end
    end
    local items =
        require("aru.agent.collect").resolve({ state = opts.invocation }, ordered_collectors)
    local blocking = {}
    for _, ref in ipairs(references) do
        if ref.context then
            items[#items + 1] = ref.context
        else
            blocking[#blocking + 1] = ref
        end
    end
    return {
        references = references,
        context = M.compose(items),
        blocking = blocking,
    }
end

---@param ref aru.agent.reference.Reference
---@param cwd string
---@param invocation_buf integer
---@return aru.agent.context.Symbol[]
function M.symbol_candidates(ref, cwd, invocation_buf)
    local source = reference_source(ref, cwd, invocation_buf)
    if not source then return {} end
    return M.symbols(source)
end

function M.clear_caches() symbol_cache = {} end

return M
