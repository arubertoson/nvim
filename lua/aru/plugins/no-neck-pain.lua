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

vim.keymap.set("n", "<leader>wo", nnp.toggle, { desc = "Toggle no-neck-pain" })

local hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
local bg = colors.tohex(hl.bg)

require("no-neck-pain").setup({
    mappings = {},
    width = 100,
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
