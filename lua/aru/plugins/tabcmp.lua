local log = require("aru.log")

local supermaven = require("supermaven-nvim")

supermaven.setup({
    disable_keymaps = true,
    condition = function()
        local name = vim.api.nvim_buf_get_name(0)
        if name:match("%.env$") then
            log.info("env file so skipping inlay completion")
            return false
        end
    end,
})

vim.api.nvim_create_autocmd("User", {
    pattern = "BlinkCmpMenuOpen",
    callback = function()
        local preview = require("supermaven-nvim.completion_preview")
        preview.on_dispose_inlay()
    end,
})

vim.keymap.set(
    "i",
    "<c-t>",
    function() require("supermaven-nvim.completion_preview").on_dispose_inlay() end
)
