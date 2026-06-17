require("mini.pairs").setup({
    modes = { insert = true, command = true, terminal = false },
})

local picker = require("aru.picker")
local pick = require("mini.pick")
pick.setup({
    source = {
        show = picker.show,
    },
    window = {
        config = picker.window_config,
        prompt_prefix = " fff  ",
    },
})
require("mini.extra").setup()
vim.ui.select = pick.ui_select

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

local ai = require("mini.ai")
require("mini.ai").setup({
    n_lines = 500,
    custom_textobjects = {

        -- Parameter
        p = ai.gen_spec.treesitter({
            a = "@parameter.inner",
            i = "@parameter.inner",
        }),

        -- Code block/conditional/loop (o = outer/around)
        o = ai.gen_spec.treesitter({ -- code block
            a = { "@block.outer", "@conditional.outer", "@loop.outer" },
            i = { "@block.inner", "@conditional.inner", "@loop.inner" },
        }),

        f = ai.gen_spec.treesitter({
            a = "@function.outer",
            i = "@function.inner",
        }),
        c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),

        t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
        d = { "%f[%d]%d+" }, -- digits
        e = { -- Word with case
            {
                "%u[%l%d]+%f[^%l%d]",
                "%f[%S][%l%d]+%f[^%l%d]",
                "%f[%P][%l%d]+%f[^%l%d]",
                "^[%l%d]+%f[^%l%d]",
            },
            "^().*()$",
        },
        g = function()
            local from = { line = 1, col = 1 }
            local to = {
                line = vim.fn.line("$"),
                col = math.max(vim.fn.getline("$"):len(), 1),
            }
            return { from = from, to = to }
        end,
        u = ai.gen_spec.function_call(), -- u for "Usage"
        U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }), -- without dot in function name
    },
})
