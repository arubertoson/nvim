---@module "lua/aru/keymaps.lua"
---
--- Dead simple keymap registry. Everything in one place.
--- When adding a keymap anywhere, come here and document it.
--- Grep this file to check for conflicts.

local with_file_mark = require("aru.jump").with_file_mark

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
map("n", "<C-o>", function() require("aru.jump").prev() end)
map("n", "<C-i>", function() require("aru.jump").next() end)
map("n", "<C-t>", function() require("aru.jump").file_toggle() end)

-- ============================================================================
-- Harpoon (quick file switching)
-- ============================================================================
map("n", "<C-h>", with_file_mark(function() require("harpoon"):list():select(1) end), { desc = "Harpoon 1" })
map("n", "<C-n>", with_file_mark(function() require("harpoon"):list():select(2) end), { desc = "Harpoon 2" })
map("n", "<C-y>", with_file_mark(function() require("harpoon"):list():select(3) end), { desc = "Harpoon 3" })

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
-- Mini.pick/Mini.extra: generic LSP, diagnostics, and vim.ui.select picker
-- Mini.surround:
-- <leader>sa = surround add
-- <leader>sd = surround delete
-- <leader>sr = surround replace
-- Mini.ai: textobjects (automatic, used with operators)

-- ============================================================================
-- Spell
-- ============================================================================
local function pick_spelling_suggestion()
    local bad = vim.fn.spellbadword()[1]
    if bad == "" then bad = vim.fn.expand("<cword>") end

    local suggestions = vim.fn.spellsuggest(bad, 10)
    if vim.tbl_isempty(suggestions) then
        vim.notify("No spelling suggestions for " .. bad, vim.log.levels.INFO)
        return
    end

    vim.ui.select(suggestions, { prompt = "Replace " .. bad .. " with:" }, function(choice)
        if not choice then return end

        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        local line = vim.api.nvim_get_current_line()
        local best_start, best_end
        local start = 1

        while true do
            local match_start, match_end = line:find(bad, start, true)
            if not match_start then break end

            if match_start - 1 <= col and col <= match_end then
                best_start, best_end = match_start, match_end
                break
            end

            if not best_start then best_start, best_end = match_start, match_end end
            start = match_end + 1
        end

        if not best_start then return end

        vim.api.nvim_buf_set_text(
            0,
            row - 1,
            best_start - 1,
            row - 1,
            best_end,
            { choice }
        )
    end)
end

map("n", "]s", "]s", { desc = "Next misspelling" })
map("n", "[s", "[s", { desc = "Previous misspelling" })
map("n", "z=", "z=", { desc = "Spelling suggestions" })
map("n", "<leader>sf", "1z=", { desc = "Fix spelling with first suggestion" })
map("n", "<leader>ss", pick_spelling_suggestion, { desc = "Pick spelling suggestion" })
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
-- <leader>p = open Pi prompt (normal: surrounding context, visual: selection)
-- <leader>P = focus/unfocus the read response float (toggle)
-- <M-h>      = previous read float page
-- <M-l>      = next read float page
-- <M-d>      = scroll read float down  (works from any buffer)
-- <M-u>      = scroll read float up    (works from any buffer)
-- q          = close read float when open, nop otherwise
-- Inside the prompt:
--   <CR>    = read/continue — float response, new or continued session
--   <C-CR>  = new session   — float response, always starts fresh session
--   <C-g>   = generate      — replace selection or insert at cursor, then select result
--   <C-p>   = session       — send to the active Pi pane

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

map(
    "n",
    "<leader>P",
    function() require("aru.agent").float.focus() end,
    { desc = "Pi: focus/unfocus read float" }
)
map(
    { "n", "i" },
    "<M-h>",
    function() require("aru.agent").float.page_prev() end,
    { desc = "Pi: previous read page" }
)
map(
    { "n", "i" },
    "<M-l>",
    function() require("aru.agent").float.page_next() end,
    { desc = "Pi: next read page" }
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

-- ============================================================================
-- Logging & Development
-- ============================================================================
map("n", "<localleader>li", function()
    local path = vim.fs.joinpath(vim.fn.stdpath("cache"), "nvim-config.log")
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.bo.buflisted = false
end, { desc = "Inspect default log"})

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
