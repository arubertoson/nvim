local log = require("aru.log")

local supermaven = require("supermaven-nvim")
local supermaven_api = require("supermaven-nvim.api")
local supermaven_preview = require("supermaven-nvim.completion_preview")

supermaven.setup({
    disable_keymaps = true,
    condition = function()
        local name = vim.api.nvim_buf_get_name(0)
        if name:match("%.env$") then
            log.info("env file so skipping inlay completion")
            return true
        end
    end,
})

vim.api.nvim_create_autocmd("User", {
    pattern = "BlinkCmpMenuOpen",
    callback = function()
        supermaven_preview.on_dispose_inlay()
    end,
})

local function toggle_supermaven_inlay()
    supermaven_preview.on_dispose_inlay()
    supermaven_api.toggle()
end

vim.keymap.set("i", "<c-t>", toggle_supermaven_inlay, {
    desc = "Toggle Supermaven inlay",
})
