---@module "aru.editor.text"
---Text-editing assistance: pairs, surroundings, and textobjects.

local ai = require("mini.ai")
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
    return pairs.closeopen('""', "[^\\\\].")
end, { expr = true, replace_keycodes = false, desc = "Insert or close double quote" })

require("mini.surround").setup({
    mappings = {
        add = "<leader>sa",
        delete = "<leader>sd",
        replace = "<leader>sr",
        find = "",
        find_left = "",
        highlight = "",
        update_n_lines = "",
        suffix_last = "",
        suffix_next = "",
    },
})

ai.setup({
    n_lines = 500,
    custom_textobjects = {
        p = ai.gen_spec.argument(),
        o = ai.gen_spec.treesitter({
            a = { "@block.outer", "@conditional.outer", "@loop.outer" },
            i = { "@block.inner", "@conditional.inner", "@loop.inner" },
        }),
        f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
        c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
        t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
        d = { "%f[%d]%d+" },
        e = {
            {
                "%u[%l%d]+%f[^%l%d]",
                "%f[%S][%l%d]+%f[^%l%d]",
                "%f[%P][%l%d]+%f[^%l%d]",
                "^[%l%d]+%f[^%l%d]",
            },
            "^().*()$",
        },
        g = function()
            return {
                from = { line = 1, col = 1 },
                to = { line = vim.fn.line("$"), col = math.max(vim.fn.getline("$"):len(), 1) },
            }
        end,
        u = ai.gen_spec.function_call(),
        U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
    },
})
