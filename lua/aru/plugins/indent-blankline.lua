local log = require("aru.log")

local ok, ibl = pcall(require, "ibl")
if not ok then
    log:error(
        ("Failed to load indent-blankline.nvim: %s, indent-blankline features will be disabled"):format(
            ibl
        )
    )
    return
end

local highlights = {
    "IBLIndentDarker",
}

local hooks = require("ibl.hooks")
hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
    local color = require("aru.colors")
    local normal = vim.api.nvim_get_hl(0, { name = "IBLIndent", link = false })
    local fg = color.shade_color(normal.fg, -0.5)
    vim.api.nvim_set_hl(0, "IBLIndentDarker", { fg = fg })
end)

ibl.setup({
    enabled = true,
    indent = {
        char = "┆",
        highlight = highlights,
    },
    scope = {
        enabled = false,
    }, -- exclude = {  -- 	filetypes = {}  -- 	buftypes = {}  -- }
})
