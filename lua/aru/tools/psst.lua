---@module "aru.tools.psst"
---Psst inquiry workflow and its editor mappings.

local map = vim.keymap.set
local layout = require("aru.workspace.layout")

require("psst").setup({
    executable = "pi-dev",
    keymaps = { global = false },
    float = {
        side = "left",
        width = 80,
        before_open = layout.expand_for_tool_float,
        after_close = layout.restore_after_tool_float,
    },
})

map("n", "q", function()
    if require("aru.interface.quick_close").close_current() then return end
    require("psst").float.close()
end, { silent = true, desc = "Close focused temporary window, else Psst response" })

map({ "n", "x" }, "<leader>p", function()
    local mode = vim.fn.mode()
    local visual_mode = (mode == "v" or mode == "V" or mode == "\22") and mode or nil
    if visual_mode then
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "x",
            false
        )
    end
    require("psst").prompt({ visual_mode = visual_mode })
end, { desc = "Psst: quick question" })

map("n", "<leader>pd", function()
    local collect = require("psst.collect").COLLECT
    require("psst").prompt({ collect = { collect.DIAGNOSTIC, collect.BLOCK } })
end, { desc = "Psst: question with cursor diagnostic" })

map("n", "<leader>P", function() require("psst").float.focus() end, {
    desc = "Psst: focus/unfocus response",
})
