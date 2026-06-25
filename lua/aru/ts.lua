---@module "aru.ts"
---
---Treesitter helpers shared across modules. Wraps nvim-treesitter-textobjects
---query iteration so callers don't duplicate parser/query boilerplate.

local M = {}

-- ============================================================================
-- Parser & query helpers
-- ============================================================================

---@class AruTs.Iterator
---@field iter fun(...): integer?, TSNode?
---@field query vim.treesitter.Query

---Returns a textobjects query iterator for the given buffer, or nil when the
---language has no parser or no textobjects query installed.
---@param bufnr number
---@return AruTs.Iterator?
function M.iter_textobj_captures(bufnr)
    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then return nil end

    local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok_parser or not parser then return nil end

    local ok_parse, trees = pcall(parser.parse, parser)
    local tree = ok_parse and trees and trees[1] or nil
    local root = tree and tree:root() or nil
    if not root then return nil end

    local ok_query, query = pcall(vim.treesitter.query.get, lang, "textobjects")
    if not ok_query or not query then return nil end

    local root_start, _, root_end, _ = root:range()

    return {
        iter = query:iter_captures(root, bufnr, root_start, root_end + 1),
        query = query,
    }
end

---Returns the text of a named field on a node, falling back to a short snippet
---from the node start when the field is absent.
---@param node TSNode
---@param field string
---@param bufnr number
---@param max_len? number   Max chars for the fallback snippet (default 10)
---@return string?
function M.node_field_text(node, field, bufnr, max_len)
    max_len = max_len or 10

    local field_node = node:field(field)[1]
    if field_node then
        local text = vim.treesitter.get_node_text(field_node, bufnr)
        if text and text ~= "" then return text end
    end

    local sr, sc = node:range()
    local line = vim.api.nvim_buf_get_lines(bufnr, sr, sr + 1, false)[1] or ""
    local end_col = math.min(#line, sc + max_len)
    local snippet = vim.api.nvim_buf_get_text(bufnr, sr, sc, sr, end_col, {})[1]
    return (snippet and snippet ~= "") and snippet or nil
end

---Returns the node at the given (0-indexed) row/col in the given buffer, or
---nil when no parser is available.
---@param bufnr number
---@param row number   0-indexed
---@param col number   0-indexed
---@return TSNode?
function M.node_at(bufnr, row, col)
    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then return nil end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then return nil end

    local ok_parse, trees = pcall(parser.parse, parser)
    local tree = ok_parse and trees and trees[1] or nil
    local root = tree and tree:root() or nil
    if not root then return nil end

    return root:named_descendant_for_range(row, col, row, col)
end

---Returns the innermost named node at the cursor in the current buffer.
---@return TSNode?
function M.node_at_cursor()
    local buf = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    return M.node_at(buf, pos[1] - 1, pos[2])
end

return M
