---@module "aru.workspace.navigation"
---Navigation history and active-file workflow provided by tracks.nvim.

local config = require("aru.config")
local map = vim.keymap.set

require("tracks").setup()

map("n", "<C-o>", function() require("tracks").point_jump.prev() end, {
    desc = "Previous buffer point",
})
map("n", "<C-i>", function() require("tracks").point_jump.next() end, {
    desc = "Next buffer point",
})
map("n", "<M-o>", function() require("tracks").file_jump.prev() end, {
    desc = "Previous file visit",
})
map("n", "<M-i>", function() require("tracks").file_jump.next() end, {
    desc = "Next file visit",
})
map("n", "<C-t>", function() require("tracks").file_jump.toggle() end, {
    desc = "Toggle previous file",
})

map("n", "<localleader>a", function() require("tracks").active.add() end, {
    desc = "Active add current file",
})
for slot, key in ipairs(config.navigation.active_file_keys) do
    local active_slot = slot
    map(
        "n",
        "<localleader>" .. key,
        function() require("tracks").active.replace(active_slot) end,
        { desc = ("Active replace slot %d"):format(active_slot) }
    )
end
map("n", "<localleader>d", function() require("tracks").active.remove() end, {
    desc = "Active remove current file",
})
map("n", "<localleader>D", function() require("tracks").active.remove_all() end, {
    desc = "Active remove all files",
})
