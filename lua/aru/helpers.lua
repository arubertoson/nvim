local M = {}

function M.debug_ts()
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[bufnr].filetype
    local lang = vim.treesitter.language.get_lang(ft)

    print("ft:", ft, "lang:", lang)

    local node = vim.treesitter.get_node({ bufnr = bufnr })

    print("node chain:")

    while node do
        local sr, sc, er, ec = node:range()
        print(("%s: row:%d col:%d -> row:%d col:%d"):format(node:type(), sr + 1, sc, er + 1, ec))
        node = node:parent()
    end

    local ok, query = pcall(vim.treesitter.query.get, lang, "textobjects")

    print("textobjects:", ok, query ~= nil)
end

function M.debug_textobjects()
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[bufnr].filetype
    local lang = vim.treesitter.language.get_lang(ft) or "unknown"
    local parser = vim.treesitter.get_parser(bufnr, lang)
    local tree = parser and parser:parse()[1] or nil
    local root = tree and tree:root() or nil
    local query = vim.treesitter.query.get(lang, "textobjects")
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1

    if not root or not query then
        print("Treesitter not available")
        return
    end

    local captures = query and query:iter_captures(root, bufnr, row, row + 1) or {}
    for id, node, _, _ in captures do
        local name = query.captures[id]
        local sr, sc, er, ec = node:range()
        print(("%s (%s): row:%d col:%d -> row:%d col:%d"):format(name, node:type(), sr + 1, sc, er + 1, ec))
    end
end

return M
