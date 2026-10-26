require("vcsigns").setup({
    target_commit = 0,
    signs = { text = { add = "▎", change = "▎" } },
})

local actions = require("vcsigns.actions")
local is_special_buffer = require("vcsigns.util").is_special_buffer
local preview = require("aru.workspace.hunk_preview")
local group = vim.api.nvim_create_augroup("aru_vc_signs", { clear = true })

vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "VimLeavePre" }, {
    group = group,
    desc = "Clear the active inline hunk preview",
    callback = preview.close,
})

local function map_buffer(bufnr)
    local opts = { buffer = bufnr, silent = true }
    vim.keymap.set("n", "]c", function() actions.hunk_next(bufnr, vim.v.count1) end, opts)
    vim.keymap.set("n", "[c", function() actions.hunk_prev(bufnr, vim.v.count1) end, opts)
    vim.keymap.set(
        "n",
        "<Space>",
        preview.toggle,
        vim.tbl_extend("force", opts, {
            desc = "Toggle inline diff for the hunk at the cursor",
        })
    )
end

vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    desc = "VCSigns file mappings",
    callback = function(args)
        if not is_special_buffer(args.buf) then map_buffer(args.buf) end
    end,
})

-- Deferred setup can run after startup or restored buffers have entered.
-- Attach directly instead of replaying BufEnter and its unrelated handlers.
for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and not is_special_buffer(bufnr) then
        map_buffer(bufnr)
        actions.start_if_needed(bufnr)
    end
end
