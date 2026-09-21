local picker = require("aru.picker")
local pick = require("mini.pick")

pick.setup({
    source = {
        show = picker.show,
    },
    window = {
        config = picker.window_config,
        prompt_prefix = "  ",
    },
})

require("mini.extra").setup()
vim.ui.select = pick.ui_select
