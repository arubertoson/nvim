local log = require("aru.log")

local ok, gitsigns = pcall(require, "gitsigns")
if not ok then
    log:error(
        ("Failed to load gitsigns.nvim: %s, gitsigns features will be disabled"):format(
            gitsigns
        )
    )
    return
end

require("gitsigns").setup({
    on_attach = function(bufnr)
        local gs = require("gitsigns")

        local nav_opts = {
            wrap = true,
            preview = true,
        }
        local key_opts = {
            buffer = bufnr,
        }

        vim.keymap.set(
            "n",
            "]c",
            function() gs.nav_hunk("next", nav_opts) end,
            key_opts
        )
        vim.keymap.set(
            "n",
            "[c",
            function() gs.nav_hunk("prev", nav_opts) end,
            key_opts
        )

        vim.keymap.set("n", "<leader>hi", gs.preview_hunk_inline, key_opts)
        vim.keymap.set("n", "<leader>hd", gs.diffthis, key_opts)
        vim.keymap.set("n", "<leader>hs", gs.stage_hunk, key_opts)
        vim.keymap.set("n", "<leader>hr", gs.reset_hunk, key_opts)

        vim.keymap.set(
            "n",
            "<leader>tb",
            gs.toggle_current_line_blame,
            key_opts
        )
    end,
})
