---@module "aru.workspace.navigation"
---Navigation history and active-file workflow provided by tracks.nvim.

local config = require("aru.config")
local map = vim.keymap.set

require("tracks").setup({ keymaps = false })

map("n", "<M-k>", function() require("tracks").point_jump.prev() end, {
    desc = "Previous buffer point",
})
map("n", "<M-j>", function() require("tracks").point_jump.next() end, {
    desc = "Next buffer point",
})
map("n", "<M-h>", function() require("tracks").file_jump.prev() end, {
    desc = "Previous file visit",
})
map("n", "<M-l>", function() require("tracks").file_jump.next() end, {
    desc = "Next file visit",
})
map("n", "<M-t>", function() require("tracks").file_jump.toggle() end, {
    desc = "Toggle previous file",
})

-- Shifted navigation targets the visible tool, regardless of cursor focus.
-- Psst takes priority when both tool windows are visible.
local function navigate_visible(delta)
    local psst = require("psst")
    if psst.float.is_visible() then
        if delta < 0 then
            psst.float.response_prev()
        else
            psst.float.response_next()
        end
        return
    end

    local sqlite = require("sqlite-scratch")
    if sqlite.is_visible() then sqlite.navigate(delta) end
end

local function scroll_visible(direction)
    local psst = require("psst")
    if psst.float.is_visible() then psst.float.scroll(direction) end
end

map("n", "<M-H>", function() navigate_visible(-1) end, {
    desc = "Previous visible response or SQLite result",
})
map("n", "<M-L>", function() navigate_visible(1) end, {
    desc = "Next visible response or SQLite result",
})
map("n", "<M-K>", function() scroll_visible("up") end, {
    desc = "Scroll visible Psst response up",
})
map("n", "<M-J>", function() scroll_visible("down") end, {
    desc = "Scroll visible Psst response down",
})

map("n", "<leader>A", function() require("tracks").active.add() end, {
    desc = "Active add current file",
})
for slot, key in ipairs(config.navigation.active_file_keys) do
    local active_slot = slot
    map(
        "n",
        "<leader>" .. key,
        function() require("tracks").active.select(active_slot) end,
        { desc = ("Active select slot %d"):format(active_slot) }
    )
end
map("n", "<leader>X", function() require("tracks").active.remove() end, {
    desc = "Active remove current file",
})
