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

local function is_enabled()
    return _G.NoNeckPain ~= nil
        and _G.NoNeckPain.state ~= nil
        and _G.NoNeckPain.state.enabled
end

local function is_regular_buffer()
    if vim.api.nvim_win_get_config(0).relative ~= "" then
        return false
    end

    if vim.bo.buftype ~= "" then
        return false
    end

    if vim.bo.filetype == "no-neck-pain" then
        return false
    end

    return true
end

local function apply_layout_for_filetype()
    if not is_enabled() or not is_regular_buffer() then
        return
    end

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

require("no-neck-pain").setup({
    mappings = {},
    width = default_width,
    minSideBufferWidth = 0,
    autocmds = {
        skipEnteringNoneckPainBuffer = true,
    },
    buffers = {
        colors = {
            background = bg,
        },
        right = { enabled = false },
    },
})
