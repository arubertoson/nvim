---@module "aru.modules.no-neck-pain"
---
--- No neck pain is my choice when it comes to setting up a centered buffer.
local log = require("aru.log")
local colors = require("aru.colors")

local ok, nnp = pcall(require, "no-neck-pain")
if not ok then
    log:error(
        ("Failed to load no-neck-pain: %s, no-neck-pain features will be disabled"):format(
            nnp
        )
    )
    return
end

local default_width = 100
local markdown_width = 90
local separator_hl = "AruNoNeckPainSeparator"
local separator_winhighlight = ("WinSeparator:%s,VertSplit:%s"):format(separator_hl, separator_hl)
local saved_winhighlight = {}

local function is_enabled()
    return _G.NoNeckPain and _G.NoNeckPain.state and _G.NoNeckPain.state.enabled
end

local function is_layout_buffer()
    return vim.api.nvim_win_get_config(0).relative == ""
        and vim.bo.buftype == ""
        and vim.bo.filetype ~= "no-neck-pain"
end

local function set_separator_highlight(win, value)
    if win and vim.api.nvim_win_is_valid(win) then
        vim.wo[win].winhighlight = value
    end
end

local function hide_separator(win)
    win = win or vim.api.nvim_get_current_win()
    saved_winhighlight[win] = saved_winhighlight[win] or vim.wo[win].winhighlight
    set_separator_highlight(win, separator_winhighlight)
end

local function restore_separators()
    for win, winhighlight in pairs(saved_winhighlight) do
        set_separator_highlight(win, winhighlight)
    end

    saved_winhighlight = {}
end

local function apply_layout_for_filetype()
    if not is_enabled() or not is_layout_buffer() then
        return
    end

    hide_separator()

    local is_markdown = vim.bo.filetype == "markdown"
    local target_width = is_markdown and markdown_width or default_width
    local right_enabled = _G.NoNeckPain.config.buffers.right.enabled

    if right_enabled ~= is_markdown then
        nnp.toggle_side("right")
    end

    if _G.NoNeckPain.config.width ~= target_width then
        nnp.resize(target_width)
    end
end

vim.keymap.set("n", "<leader>wo", function()
    nnp.toggle()
    vim.defer_fn(apply_layout_for_filetype, 50)
end, { desc = "Toggle no-neck-pain" })

vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    group = vim.api.nvim_create_augroup("AruNoNeckPainFiletypeLayout", { clear = true }),
    callback = function()
        vim.defer_fn(apply_layout_for_filetype, 50)
    end,
})

local hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
local bg = colors.tohex(hl.bg)

vim.api.nvim_set_hl(0, separator_hl, { fg = bg, bg = bg })

require("no-neck-pain").setup({
    mappings = {},
    width = default_width,
    minSideBufferWidth = 0,
    autocmds = {
        skipEnteringNoNeckPainBuffer = true,
    },
    callbacks = {
        postEnable = function(state)
            vim.defer_fn(function()
                hide_separator(state.previously_focused_win)
            end, 50)
        end,
        postDisable = restore_separators,
    },
    buffers = {
        colors = {
            background = bg,
        },
        wo = {
            winhighlight = separator_winhighlight,
        },
        right = { enabled = false },
    },
})
