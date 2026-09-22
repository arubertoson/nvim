---@module "aru.editor.keymaps"
---Universal editor mappings. Feature mappings live with their owning behavior.

local config = require("aru.config")
local map = vim.keymap.set

vim.g.mapleader = config.keys.leader
vim.g.maplocalleader = config.keys.local_leader

map({ "n", "x", "o" }, config.keys.leader, "<Nop>", { silent = true })
map({ "n", "x", "o" }, config.keys.local_leader, "<Nop>", { silent = true })

-- Do not skip wrapped screen lines.
map({ "n", "x", "o" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })
map({ "n", "x", "o" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })

map("v", "<", "<gv", { noremap = true, silent = true })
map("v", ">", ">gv", { noremap = true, silent = true })
map("n", "<C-d>", "v:count ? '<C-d>zz' : (winheight('.') / 2) . '<C-d>zz'", { expr = true })
map("n", "<C-u>", "v:count ? '<C-u>zz' : (winheight('.') / 2) . '<C-u>zz'", { expr = true })

map("c", "<C-h>", "<Left>")
map("c", "<C-l>", "<Right>")
map("c", "<C-p>", "<Down>")
map("c", "<C-n>", "<Up>")
map("c", "<C-d>", "<Del>")
map("c", "<C-a>", "<Home>")
map("c", "<C-e>", "<End>")
map("c", "<C-n>", function()
    if vim.fn.getcmdtype() == "/" or vim.fn.getcmdtype() == "?" then return "<C-g>" end
    return "<C-n>"
end, { expr = true })
map("c", "<C-p>", function()
    if vim.fn.getcmdtype() == "/" or vim.fn.getcmdtype() == "?" then return "<C-t>" end
    return "<C-p>"
end, { expr = true })

map("t", "<C-\\><C-\\>", "<C-\\><C-n>", { silent = true })

map("n", "<localleader>q", ":<C-u>qa<CR>", { desc = "Exit Neovim" })
map("n", "<localleader>C", ":<C-u>bd<CR>", { desc = "Delete buffer" })
map("n", "<localleader>c", ":<C-u>wincmd c<CR>", { desc = "Close split" })

map("n", "<leader>;", "<CMD>:noh<CR>", { desc = "Clear search highlight", silent = true })
map("n", "<localleader>r", ":%s:<C-R><C-w>::g<left><left>", { desc = "Replace word under cursor" })
map(
    "n",
    "<localleader>R",
    ":%s:<C-R><C-w>:<C-r><C-w>:<Left>",
    { desc = "Replace word under cursor" }
)

map("n", "<leader>k", ":help ", { desc = "Help tag" })

vim.keymap.set("x", "R", function() vim.treesitter.select("parent") end, {
    desc = "Select parent Treesitter node",
})
