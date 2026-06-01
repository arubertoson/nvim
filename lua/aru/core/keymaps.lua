---@module "lua/aru/keymaps.lua"
---
--- Dead simple keymap registry. Everything in one place.
--- When adding a keymap anywhere, come here and document it.
--- Grep this file to check for conflicts.

local map = vim.keymap.set

-- ============================================================================
-- Leaders
-- ============================================================================
vim.g.mapleader = ";"
vim.g.maplocalleader = ","

-- ============================================================================
-- Nops (disable defaults)
-- ============================================================================
map({ "n", "x", "o" }, ";", "<Nop>", { silent = true })
map({ "n", "x", "o" }, ",", "<Nop>", { silent = true })
map("n", "q", "<Nop>", { silent = true })
map("n", "Q", "<Nop>", { silent = true })

-- ============================================================================
-- Core Movement & Editing
-- ============================================================================
-- Don't skip wrap lines
map({ "n", "x", "o" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })
map({ "n", "x", "o" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })

-- Better visual mode indenting
map("v", "<", "<gv", { noremap = true, silent = true })
map("v", ">", ">gv", { noremap = true, silent = true })

-- Scroll and center
map("n", "<C-d>", "v:count ? '<C-d>zz' : (winheight('.') / 2) . '<C-d>zz'", { expr = true })
map("n", "<C-u>", "v:count ? '<C-u>zz' : (winheight('.') / 2) . '<C-u>zz'", { expr = true })

-- ============================================================================
-- Command Mode
-- ============================================================================
map("c", "<C-h>", "<Left>")
map("c", "<C-l>", "<Right>")
map("c", "<C-p>", "<Down>")
map("c", "<C-n>", "<Up>")
map("c", "<C-d>", "<Del>")
map("c", "<C-a>", "<Home>")
map("c", "<C-e>", "<End>")

-- ============================================================================
-- Terminal Mode
-- ============================================================================
map("t", "<C-\\><C-\\>", "<C-\\><C-n>", { silent = true })

-- ============================================================================
-- Buffer/Window Control
-- ============================================================================
map("n", "<localleader>q", ":<C-u>qa<CR>", { desc = "Exit neovim" })
map("n", "<localleader>C", ":<C-u>bd<CR>", { desc = "Delete buffer" })
map("n", "<localleader>c", ":<C-u>wincmd c<CR>", { desc = "Close split" })

-- ============================================================================
-- Search & Replace
-- ============================================================================
map("n", "<leader>;", "<CMD>:noh<CR>", { desc = "Clear search highlight", silent = true })
map("n", "<localleader>r", ":%s:<C-R><C-w>::g<left><left>", { desc = "Replace word under cursor" })
map(
    "n",
    "<localleader>R",
    ":%s:<C-R><C-w>:<C-r><C-w>:<Left>",
    { desc = "Replace word under cursor" }
)

-- Map Ctrl+n to Next match in search mode
map("c", "<C-n>", function()
    if vim.fn.getcmdtype() == "/" or vim.fn.getcmdtype() == "?" then return "<C-g>" end
    return "<C-n>"
end, { expr = true })

-- Map Ctrl+p to Previous match in search mode
map("c", "<C-p>", function()
    if vim.fn.getcmdtype() == "/" or vim.fn.getcmdtype() == "?" then return "<C-t>" end
    return "<C-p>"
end, { expr = true })

-- ============================================================================
-- LSP (set in LspAttach autocmd, but documented here)
-- ============================================================================
-- Global LSP actions (always available):
-- grn     = vim.lsp.buf.rename
-- M      = vim.diagnostic.open_float
-- K      = vim.lsp.buf.hover
-- ]d     = vim.diagnostic.jump (next)
-- [d     = vim.diagnostic.jump (prev)
--
-- <leader>l* namespace (LSP actions):
-- <leader>lf = vim.lsp.buf.format
-- <leader>ld = toggle diagnostics
-- <leader>lh = toggle inlay hints
-- <leader>li = :checkhealth vim.lsp
-- <leader>lc = vim.lsp.codelens.run (if supported)
-- <leader>ls = vim.lsp.buf.signature_help (if supported)
-- <leader>lt = vim.lsp.buf.typehierarchy("supertypes") (if supported)
--
-- <leader>w* namespace (workspace):
-- <leader>ws = vim.lsp.buf.workspace_symbol
-- <leader>wa = vim.lsp.buf.add_workspace_folder
-- <leader>wr = vim.lsp.buf.remove_workspace_folder
-- <leader>wl = print workspace folders
-- <leader>wo = toggle no-neck-pain
--
-- <leader>o* namespace (organize):
-- <leader>oi = organize imports (code action)
--
-- <leader>t* namespace (toggle):
-- <leader>tv = toggle virtual text diagnostics

map("n", "<leader>lf", vim.lsp.buf.format, { desc = "LSP format buffer" })
map(
    "n",
    "<leader>ld",
    function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end,
    { desc = "Toggle diagnostics" }
)
map(
    "n",
    "<leader>lh",
    function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end,
    { desc = "Toggle inlay hints" }
)
map("n", "<leader>li", "<cmd>checkhealth vim.lsp<CR>", { desc = "LSP info" })

-- ============================================================================
-- FZF-Lua (fuzzy finding)
-- ============================================================================
-- <leader>f* namespace (find):
local with_file_mark = require("aru.jump").with_file_mark

map(
    "n",
    "<leader>ff",
     with_file_mark(function() require("fzf-lua").files({ cwd = vim.uv.cwd() }) end),
    { desc = "Find files" }
)

map(
    "n",
    "<leader>fs",
    function() require("fzf-lua").lgrep_curbuf() end,
    { desc = "Find string (live grep)" }
)
map(
    "n",
    "<leader>fS",
    with_file_mark(function() require("fzf-lua").live_grep() end),
    { desc = "Find string (live grep)" }
)
map("n", "<leader>k", function() require("fzf-lua").help_tags() end, { desc = "Find help tags" })

-- LSP pickers (set in LspAttach, documented here):
-- fs = lsp_document_symbols
-- fS = lsp_live_workspace_symbols
-- fd = lsp_document_diagnostics
-- fD = lsp_workspace_diagnostics
-- gd = lsp_definitions
-- gr = lsp_references
-- go = lsp_code_actions
-- gi = lsp_implementations
-- gy = lsp_typedefs

--
map("n", "<C-o>", function() require("aru.jump").prev() end)
map("n", "<C-i>", function() require("aru.jump").next() end)
map("n", "<C-t>", function() require("aru.jump").file_toggle() end)

-- ============================================================================
-- Harpoon (quick file switching)
-- ============================================================================
map("n", "<C-h>", function() require("harpoon"):list():select(1) end, { desc = "Harpoon 1" })
map("n", "<C-n>", function() require("harpoon"):list():select(2) end, { desc = "Harpoon 2" })
map("n", "<C-y>", function() require("harpoon"):list():select(3) end, { desc = "Harpoon 3" })

map(
    "n",
    "<localleader>a",
    function() require("harpoon"):list():add() end,
    { desc = "Harpoon add" }
)
map(
    "n",
    "<localleader>m",
    function() require("harpoon").ui:toggle_quick_menu(require("harpoon"):list()) end,
    { desc = "Harpoon menu" }
)
map("n", "<localleader>d", function()
    local list = require("harpoon"):list()

    local rel_path = vim.fs.relpath(vim.uv.cwd() or "", vim.api.nvim_buf_get_name(0))
    local item, idx = list:get_by_value(rel_path)
    if item then list:remove_at(idx) end
end, { desc = "Harpoon remove current" })

-- ============================================================================
-- Leap (motion)
-- ============================================================================

vim.keymap.set({ "n", "x", "o" }, "s", "<Plug>(leap)")
vim.keymap.set({ "x", "o" }, "R", function()
    require("leap.treesitter").select({
        -- To increase/decrease the selection in a clever-f-like manner,
        -- with the trigger key itself (vRRRRrr...). The default keys
        -- (<enter>/<backspace>) also work, so feel free to skip this.
        opts = require("leap.user").with_traversal_keys("R", "r"),
    })
end)

-- ============================================================================
-- Git (gitsigns)
-- ============================================================================
-- <leader>h* namespace (hunks) - set in gitsigns on_attach:
-- ]c = next hunk
-- [c = prev hunk
-- <leader>hi = preview hunk inline
-- <leader>hd = diff this
-- <leader>hs = stage hunk
-- <leader>hr = reset hunk
-- <leader>tb = toggle current line blame

-- ============================================================================
-- Completion & Snippets
-- ============================================================================

local cmp = require("aru.cmp")

vim.keymap.set({ "i", "s" }, "<Tab>", cmp.tab_forward, { silent = true })
vim.keymap.set({ "i", "s" }, "<S-Tab>", cmp.tab_backward, { silent = true })
vim.keymap.set({ "i", "s" }, "<C-l>", cmp.smart_accept, { silent = true })

-- ============================================================================
-- Oil (file explorer)
-- ============================================================================
map("n", "<leader>n", function()
    if vim.bo[0].filetype == "oil" then
        require("oil").discard_all_changes()
        require("oil").close()
    else
        require("oil").open_float()
    end
end, { desc = "Toggle Oil (current dir)" })

map("n", "<leader>N", function()
    if vim.bo[0].filetype == "oil" then
        require("oil").discard_all_changes()
        require("oil").close()
    else
        require("oil").open_float(vim.fn.getcwd())
    end
end, { desc = "Toggle Oil (cwd)" })

-- Oil internal mappings (set in oil.setup):
-- q      = close
-- <C-k>  = parent directory
-- <C-j>  = select
-- <C-p>  = preview

-- ============================================================================
-- Mini.nvim
-- ============================================================================
-- Mini.pairs: auto-pairs in insert/command mode (automatic)
-- Mini.surround:
-- <leader>sa = surround add
-- <leader>sd = surround delete
-- <leader>sr = surround replace
-- Mini.ai: textobjects (automatic, used with operators)

-- ============================================================================
-- No-Neck-Pain (centered buffer)
-- ============================================================================
map(
    "n",
    "<leader>wo",
    function() require("no-neck-pain").toggle() end,
    { desc = "Toggle no-neck-pain" }
)

-- ============================================================================
-- Logging & Development
-- ============================================================================
map("n", "<localleader>li", ":buffer LOG-default<CR>", { desc = "Inspect default log" })

-- Lua REPL (ftplugin/lua.lua - only in lua files):
-- <leader>rr = run current buffer
-- <leader>rl = run current line
-- <leader>rs = run visual selection (visual mode)
-- <leader>re = re-run last chunk

-- ============================================================================
-- Notes on Conflicting/Overlapping Keymaps
-- ============================================================================
-- <C-h>, <C-n> are used for both Harpoon and command mode navigation
-- This is intentional - context determines behavior (normal vs command mode)
--
-- <leader>l* is LSP namespace, avoid using for other features
-- <leader>f* is Find (FZF) namespace
-- <leader>h* is Git hunk namespace
-- <leader>w* is Workspace namespace
-- <leader>t* is Toggle namespace
-- <leader>r* is Run/REPL namespace (lua files)
-- <localleader>* is buffer-local actions (quit, close, delete)
