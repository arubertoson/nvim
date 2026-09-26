require("vcsigns").setup({ target_commit = 1 })

local actions = require("vcsigns.actions")

vim.api.nvim_create_autocmd("BufEnter", {
    desc = "VCSigns file mappings",
    callback = function(args)
        local bufnr = args.buf
        if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then return end

        local opts = { buffer = bufnr }
        vim.keymap.set("n", "]c", function() actions.hunk_next(bufnr, vim.v.count1) end, opts)
        vim.keymap.set("n", "[c", function() actions.hunk_prev(bufnr, vim.v.count1) end, opts)
        vim.keymap.set({ "n", "x" }, "<leader>hr", function() actions.hunk_undo(bufnr) end, opts)
        vim.keymap.set("n", "<leader>hi", function() actions.toggle_hunk_diff(bufnr) end, opts)
        vim.keymap.set("n", "<leader>hd", function() actions.diffview(bufnr) end, opts)
    end,
})
