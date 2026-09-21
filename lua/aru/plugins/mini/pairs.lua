local pairs = require("mini.pairs")

pairs.setup({
    modes = { insert = true, command = true, terminal = false },
})

local function has_unclosed_double_quote_before_cursor()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local prefix = line:sub(1, col)
    local quote_count = 0
    local backslash_count = 0

    for i = 1, #prefix do
        local char = prefix:sub(i, i)
        if char == "\\" then
            backslash_count = backslash_count + 1
        else
            if char == '"' and backslash_count % 2 == 0 then quote_count = quote_count + 1 end
            backslash_count = 0
        end
    end

    return quote_count % 2 == 1
end

vim.keymap.set("i", '"', function()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    if line:sub(col + 1, col + 1) ~= '"' and has_unclosed_double_quote_before_cursor() then
        return '"'
    end
    return pairs.closeopen('""', "[^\\].")
end, { expr = true, replace_keycodes = false, desc = "Insert or close double quote" })
