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
map("n", "q", function()
    if require("aru.quick_close").close_current() then return end
    require("aru.agent").float.close()
end, { silent = true, desc = "Close focused temporary window, else Pi read float" })

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
-- <leader>lf = format through Conform
-- <leader>ld = toggle diagnostics
-- <leader>lh = toggle inlay hints
-- <leader>li = :checkhealth vim.lsp
-- <leader>lc = vim.lsp.codelens.run (if supported)
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

map(
    "n",
    "<leader>lf",
    function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
    { desc = "Format file" }
)
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
-- Help
-- ============================================================================
map("n", "<leader>k", ":help ", { desc = "Help tag" })

-- LSP defaults (set in LspAttach, documented here):
-- fs = document symbols
-- fS = workspace symbols
-- fd = buffer diagnostics picker
-- fD = workspace diagnostics picker
-- gd = definition
-- gr = references
-- go = code actions
-- gi = implementations
-- gy = type definitions

--
map(
    "n",
    "<C-o>",
    function() require("aru.nav").point_jump.prev() end,
    { desc = "Previous buffer point" }
)
map(
    "n",
    "<C-i>",
    function() require("aru.nav").point_jump.next() end,
    { desc = "Next buffer point" }
)
map(
    "n",
    "<M-o>",
    function() require("aru.nav").file_jump.prev() end,
    { desc = "Previous file visit" }
)
map("n", "<M-i>", function() require("aru.nav").file_jump.next() end, { desc = "Next file visit" })
map(
    "n",
    "<C-t>",
    function() require("aru.nav").file_jump.toggle() end,
    { desc = "Toggle previous file" }
)

-- ============================================================================
-- Active files
-- ============================================================================
map(
    "n",
    "<localleader>a",
    function() require("aru.nav").active.add() end,
    { desc = "Active add current file" }
)
map(
    "n",
    "<localleader>j",
    function() require("aru.nav").active.replace(1) end,
    { desc = "Active replace slot 1" }
)
map(
    "n",
    "<localleader>k",
    function() require("aru.nav").active.replace(2) end,
    { desc = "Active replace slot 2" }
)
map(
    "n",
    "<localleader>l",
    function() require("aru.nav").active.replace(3) end,
    { desc = "Active replace slot 3" }
)
map(
    "n",
    "<localleader>d",
    function() require("aru.nav").active.remove() end,
    { desc = "Active remove current file" }
)
map(
    "n",
    "<localleader>D",
    function() require("aru.nav").active.remove_all() end,
    { desc = "Active remove all files" }
)

-- ============================================================================
-- Treesitter node selection
-- ============================================================================

vim.keymap.set("x", "R", function() vim.treesitter.select("parent") end, {
    desc = "Select parent Treesitter node",
})

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

local function blink_action(action)
    return function() return require("aru.plugins.blink")[action]() end
end

vim.keymap.set({ "i", "s" }, "<Tab>", blink_action("tab_forward"), { silent = true })
vim.keymap.set({ "i", "s" }, "<S-Tab>", blink_action("tab_backward"), { silent = true })
vim.keymap.set({ "i", "s" }, "<C-l>", blink_action("complete"), { silent = true })

-- ============================================================================
-- Oil (file explorer)
-- ============================================================================
map("n", "<leader>n", function() require("aru.oil").toggle() end, {
    desc = "Toggle Oil (current dir)",
})

map("n", "<leader>N", function() require("aru.oil").toggle_cwd() end, {
    desc = "Toggle Oil (cwd)",
})

-- Oil internal mappings (set in oil.setup):
-- q      = close
-- <C-k>  = parent directory
-- <C-j>  = select
-- <C-p>  = preview

-- ============================================================================
-- Mini.nvim
-- ============================================================================
-- Mini.pairs: auto-pairs in insert/command mode (automatic)
-- Mini.pick/Mini.extra: generic LSP, diagnostics, and vim.ui.select picker
-- Mini.surround:
-- <leader>sa = surround add
-- <leader>sd = surround delete
-- <leader>sr = surround replace
-- Mini.ai: textobjects (automatic, used with operators)
-- Custom object reference and examples: docs/mini-ai.md

-- ============================================================================
-- Spell
-- ============================================================================
map("n", "]s", "]s", { desc = "Next misspelling" })
map("n", "[s", "[s", { desc = "Previous misspelling" })
map("n", "z=", "z=", { desc = "Spelling suggestions" })
map("n", "<leader>sf", "1z=", { desc = "Fix spelling with first suggestion" })
map(
    "n",
    "<leader>ss",
    function() require("aru.core.spell").pick_suggestion() end,
    { desc = "Pick spelling suggestion" }
)
map("n", "<leader>ts", ":set spell!<CR>", { desc = "Toggle spell check" })

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
-- Agent (Pi)
-- ============================================================================
-- <leader>p  = open Pi prompt (normal: surrounding context, visual: selection)
-- <leader>pd = open Pi prompt with the diagnostic at the cursor
-- <leader>P  = focus/unfocus the read response float (toggle)
-- <M-h>      = previous response in the selected Agent Session
-- <M-l>      = next response in the selected Agent Session
-- <M-H>      = previous Agent Session
-- <M-L>      = next Agent Session
-- <M-d>      = scroll read float down  (works from any buffer)
-- <M-u>      = scroll read float up    (works from any buffer)
-- q          = close read float when open, nop otherwise
-- Inside the prompt:
--   <CR>    = read/continue — float response, new or continued session
--   <C-CR>  = new session   — float response, always starts fresh session
--   <C-g>   = generate      — replace selection or insert at cursor, then select result
--   <C-p>   = session       — send to the active Pi pane
--   <M-CR>  = newline

map({ "n", "x" }, "<leader>p", function()
    -- Exit visual mode first so getpos("'<") / getpos("'>") are set correctly.
    local mode = vim.fn.mode()
    local visual_mode = (mode == "v" or mode == "V" or mode == "\22") and mode or nil
    if visual_mode then
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "x",
            false
        )
    end
    require("aru.agent").prompt({ visual_mode = visual_mode })
end, { desc = "Pi: open prompt" })

map("n", "<leader>pd", function()
    local collect = require("aru.agent.collect").COLLECT
    require("aru.agent").prompt({
        collect = { collect.DIAGNOSTIC, collect.BLOCK },
    })
end, { desc = "Pi: prompt with cursor diagnostic" })

map(
    "n",
    "<leader>P",
    function() require("aru.agent").float.focus() end,
    { desc = "Pi: focus/unfocus read float" }
)
map(
    { "n", "i" },
    "<M-h>",
    function() require("aru.agent").float.response_prev() end,
    { desc = "Pi: previous response" }
)
map(
    { "n", "i" },
    "<M-l>",
    function() require("aru.agent").float.response_next() end,
    { desc = "Pi: next response" }
)
map(
    { "n", "i" },
    "<M-H>",
    function() require("aru.agent").float.session_prev() end,
    { desc = "Pi: previous Agent Session" }
)
map(
    { "n", "i" },
    "<M-L>",
    function() require("aru.agent").float.session_next() end,
    { desc = "Pi: next Agent Session" }
)
map(
    { "n", "i" },
    "<M-d>",
    function() require("aru.agent").float.scroll("down") end,
    { desc = "Pi: scroll float down" }
)
map(
    { "n", "i" },
    "<M-u>",
    function() require("aru.agent").float.scroll("up") end,
    { desc = "Pi: scroll float up" }
)

-- Lua REPL (ftplugin/lua.lua - only in lua files):
-- <leader>rr = run current buffer
-- <leader>rl = run current line
-- <leader>rs = run visual selection (visual mode)
-- <leader>re = re-run last chunk

-- ============================================================================
-- Notes on Conflicting/Overlapping Keymaps
-- ============================================================================
-- <C-h>, <C-n> are used for both active-file slots and command mode navigation
-- This is intentional - context determines behavior (normal vs command mode)
--
-- <leader>l* is LSP namespace, avoid using for other features
-- <leader>f* is Find (FZF) namespace
-- <leader>h* is Git hunk namespace
-- <leader>w* is Workspace namespace
-- <leader>t* is Toggle namespace
-- <leader>r* is Run/REPL namespace (lua files)
-- <localleader>* is buffer-local actions (quit, close, delete)
