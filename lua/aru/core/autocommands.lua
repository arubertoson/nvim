local log = require("aru.log")
local custom = require("aru.custom")

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

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = vim.api.nvim_create_augroup("aru_activate_treesitter_on_filetype", { clear = true }),
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
            local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

            log.debug("Treesitter failed to start", bufname, ft)
            return
        end

        local winid = vim.api.nvim_get_current_win()
        vim.wo[winid].foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
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

local reload_group =
    vim.api.nvim_create_augroup("aru_ensure_buffer_is_reloaded_if_updated", { clear = true })

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
    group = reload_group,
    desc = "Check whether open files were changed outside Neovim",
    callback = function()
        if vim.fn.getcmdwintype() == "" then vim.cmd.checktime() end
    end,
})

vim.api.nvim_create_autocmd("FileChangedShell", {
    group = reload_group,
    desc = "Reload files changed outside Neovim without prompting",
    callback = function() vim.v.fcs_choice = "reload" end,
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

local autosave_group =
    vim.api.nvim_create_augroup("aru_buffer_autosave_on_events", { clear = true })
local autosave_delay = 100
local autosave_excluded = {}
---@type table<integer, { timer: uv.uv_timer_t, generation: integer }>
local autosave_timers = {}

---@param bufnr integer
local function can_save(bufnr)
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })

    return empty(buftype)
        and not empty(filetype)
        and modifiable
        and not vim.tbl_contains(autosave_excluded, filetype)
        and vim.uv.fs_stat(vim.api.nvim_buf_get_name(bufnr)) ~= nil
end

---@param bufnr integer
local function save_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return
    end
    if not can_save(bufnr) then return end

    vim.cmd(("checktime %d"):format(bufnr))
    vim.api.nvim_buf_call(bufnr, function() vim.cmd.update() end)
end

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = autosave_group,
    desc = "Save changed buffers after a short idle period",
    callback = function(ev)
        local bufnr = ev.buf
        local pending = autosave_timers[bufnr]
        if not pending then
            local timer = assert(vim.uv.new_timer())
            pending = { timer = timer, generation = 0 }
            autosave_timers[bufnr] = pending
        end

        pending.generation = pending.generation + 1
        local generation = pending.generation
        pending.timer:stop()
        pending.timer:start(
            autosave_delay,
            0,
            vim.schedule_wrap(function()
                if autosave_timers[bufnr] ~= pending or pending.generation ~= generation then
                    return
                end

                autosave_timers[bufnr] = nil
                pending.timer:close()
                save_buffer(bufnr)
            end)
        )
    end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
    group = autosave_group,
    desc = "Cancel pending autosave for destroyed buffers",
    callback = function(ev)
        local pending = autosave_timers[ev.buf]
        if not pending then return end

        autosave_timers[ev.buf] = nil
        pending.timer:stop()
        pending.timer:close()
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
