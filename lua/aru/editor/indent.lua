---@module "aru.editor.indent"
---Indent-guide presentation for editable buffers.

local log = require("aru.log")

local ok, ibl = pcall(require, "ibl")
if not ok then
    log.error("Failed to load indent-blankline.nvim; its features are disabled", ibl)
    return
end

local highlights = { "IBLIndentDarker" }
local hooks = require("ibl.hooks")
hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
    local colors = require("aru.interface.colors")
    local normal = vim.api.nvim_get_hl(0, { name = "IBLIndent", link = false })
    vim.api.nvim_set_hl(0, "IBLIndentDarker", { fg = colors.shade_color(normal.fg, -0.5) })
end)

ibl.setup({
    enabled = true,
    indent = {
        char = "┆",
        highlight = highlights,
    },
    scope = { enabled = false },
})
