local log = require("aru.log")
local custom = require("aru.custom")

vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup(
        "gmr_avoid_comment_new_line",
        { clear = true }
    ),
    desc = "Avoid comment on new line",
    command = "set formatoptions-=cro",
})

vim.api.nvim_create_autocmd("TextYankPost", {
    group = vim.api.nvim_create_augroup(
        "aru_highlight_on_yank",
        { clear = true }
    ),
    desc = "Highlight when yanking (copying) text",
    callback = function() vim.highlight.on_yank() end,
})

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = vim.api.nvim_create_augroup(
        "aru_activate_treesitter_on_filetype",
        { clear = true }
    ),
    pattern = custom.treesitter_parsers,
    desc = "When editing a file which is a valid treesitter parser (authored file list), we activate treesitter",
    callback = function(ev)
        -- Lazy version, it's going to try to start the treesitter parser for every
        -- filetyp, this will trigger on all things that open a buffer in neovim
        -- and it's a bit unyieldy. But it works.
        local ok, _ = pcall(vim.treesitter.start)
        if not ok then
            local bufnr = vim.api.nvim_get_current_buf()
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            local ft =
                vim.api.nvim_get_option_value("filetype", { buf = bufnr })

            log:debug(
                ("Treesitter failed to start: %s, %s"):format(bufname, ft)
            )
            return
        end

        local winid = vim.api.nvim_get_current_win()
        vim.wo[winid].foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.bo[ev.buf].indentexpr =
            "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
})

local number_exclude_ft =
    { "markdown", "telekasten", "dbui", "dbout", "oil", "help" }
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
    pattern = {
        "help",
        "git-status",
        "git-log",
        "gitcommit",
        "notify",
        "checkhealth",
        "dbui",
        "log",
        "qf",
        "lspinfo",
    },
    callback = function()
        local function smart_close()
            if vim.fn.winnr("$") ~= 1 then vim.api.nvim_win_close(0, true) end
        end

        vim.keymap.set(
            "n",
            "q",
            smart_close,
            { buffer = 0, nowait = true, silent = true }
        )
    end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
    group = vim.api.nvim_create_augroup(
        "aru_ensure_buffer_is_reloaded_if_updated",
        { clear = true }
    ),
    desc = [[
We make a best effort attempt to always work with the latest file,
no matter if it's been updated from other sources or not.
]],
    callback = function()
        if vim.fn.getcmdwintype() == "" then
            -- Checktime detects external changes to the file, if 'autoread' is set and there are no
            -- unsaved changes it will auto-reload. Otherwise it will prompt the user to save changes
            -- or discard them.
            vim.cmd("silent! checktime")
        end
    end,
})

---Determine if a value of any type is empty
---@param item any
---@return boolean
local function empty(item)
    if not item then return true end

    local item_type = type(item)
    if item_type == "string" then
        return item == ""
    elseif item_type == "table" then
        return vim.tbl_isempty(item)
    end

    return true
end

-- vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "CursorHold" }, {
vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
    desc = [[
Save on insert, buffer leave, cursor hold--we want to save as often as
possible, be it manual or automatic.",
]],
    group = vim.api.nvim_create_augroup(
        "aru_buffer_autosave_on_events",
        { clear = true }
    ),
    nested = true,
    callback = function()
        local save_excluded = {}

        ---We want to only save on certain filetypes and if the buffer in question
        ---supports it. This should be tweaked accordingly.
        ---@return boolean
        local function can_save()
            return empty(vim.bo.buftype)
                and not empty(vim.bo.filetype)
                and vim.bo.modifiable
                and not vim.tbl_contains(save_excluded, vim.bo.filetype)
        end

        -- Prevent save on non existing files, files needs to be
        -- created with intent before we go into autosave mode.
        if vim.uv.fs_stat(vim.api.nvim_buf_get_name(0)) == nil then return end

        if can_save() then
            -- vim.cmd("silent! update")
            vim.api.nvim_buf_call(0, function() vim.cmd("silent! write") end)
        end
    end,
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
