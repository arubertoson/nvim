vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("gmr_avoid_comment_new_line", { clear = true }),
    desc = "Avoid comment on new line",
    command = "set formatoptions-=cro",
})

vim.api.nvim_create_autocmd("TextYankPost", {
    group = vim.api.nvim_create_augroup("aru_highlight_on_yank", { clear = true }),
    desc = "Highlight when yanking (copying) text",
    callback = function() vim.highlight.on_yank() end,
})

vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("aru_activate_treesitter_on_filetype", { clear = true }),
    desc = "Activate Treesitter when the filetype has an available parser",
    callback = function(ev)
        local ok = pcall(vim.treesitter.start, ev.buf)
        if not ok then return end

        vim.bo[ev.buf].indentexpr = require("nvim-treesitter").indentexpr
    end,
})

local number_exclude_ft = { "markdown", "dbui", "dbout", "oil", "help" }
local number_exclude_bt = { "terminal" }
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = vim.api.nvim_create_augroup(
        "aru_handle_signcolumn_per_buffer_number",
        { clear = true }
    ),
    desc = "Handle signcolumn per buffer, depending on filetype and buftype we set it to custom values.",
    pattern = { "*?" },
    callback = function()
        if
            vim.tbl_contains(number_exclude_ft, vim.bo.filetype)
            or vim.tbl_contains(number_exclude_bt, vim.bo.buftype)
        then
            return nil
        end

        vim.opt_local.number = true
        vim.opt_local.relativenumber = true
        vim.opt_local.numberwidth = 3 -- Set minimum number column width
        vim.opt_local.signcolumn = "yes:1" -- Always show sign column to prevent reflo
        -- Combine line number and sign column visually
        vim.opt_local.statuscolumn = "%l%s"
    end,
})

vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    group = "aru_handle_signcolumn_per_buffer_number",
    desc = "On leave, restore default values.",
    pattern = { "*?" },
    callback = function()
        if
            vim.tbl_contains(number_exclude_ft, vim.bo.filetype)
            or vim.tbl_contains(number_exclude_bt, vim.bo.buftype)
        then
            return nil
        end

        vim.opt_local.number = true
        vim.opt_local.relativenumber = false
        -- We don't explicitly set numberwidth or signcolumn to defaults on leave,
        -- as WinEnter/BufEnter will set them correctly when re-entering.
        -- This also allows other autocmds (like for terminals) to override.
    end,
})

vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("aru_quick_close", { clear = true }),
    desc = "Set a local <q> mapping to close the buffer, these buffers are temporary.",
    pattern = require("aru.quick_close").filetypes,
    callback = function(ev) require("aru.quick_close").map_buffer(ev.buf) end,
})

vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = vim.api.nvim_create_augroup(
        "aru_ensure_cmdheight_when_typing_command",
        { clear = true }
    ),
    desc = "Don't hide the status line when typing a command",
    command = ":set cmdheight=1",
})

vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = vim.api.nvim_create_augroup(
        "aru_ensure_cmdheight_when_not_typing_command",
        { clear = true }
    ),
    desc = "Hide cmdline when not typing a command",
    command = ":set cmdheight=0",
})
