---@module 'spec'
---This file is used to define what plugins we need to fetch. The builtint
---pack handles downloading and calling packadd making the plugins available
---to require.
---
---We are also ensuring that we don't use load (to source plugin/ location)
---and to autoconfirm.

--- XXX: Check out:
--- - obsidian.nvim
--- - zk (zettelkasten)
---

vim.pack.add({
    -- ===========================================================================
    -- Libs
    -- ===========================================================================
    {
        src = "https://github.com/nvim-lua/plenary.nvim.git",
        version = "master",
    },
    {
        src = "https://github.com/nvim-tree/nvim-web-devicons",
        version = "master",
    },
    {
        src = "https://github.com/nvim-treesitter/nvim-treesitter",
        version = "main",
    },
    {
        src = "https://github.com/nvim-treesitter/nvim-treesitter-textobjects",
        version = "main",
    },

    { src = "https://github.com/niba/continue.nvim", version = "main" },
    -- ===========================================================================
    -- Themes
    -- ===========================================================================
    { src = "https://github.com/thesimonho/kanagawa-paper.nvim" },
    { src = "https://github.com/rebelot/kanagawa.nvim" },

    -- UI Stuff
    {
        src = "https://github.com/lewis6991/gitsigns.nvim",
        version = vim.version.range("2.1.0"),
    },
    {
        src = "https://github.com/lukas-reineke/indent-blankline.nvim",
        version = vim.version.range("3.9.1"),
    },
    {
        src = "https://github.com/shortcuts/no-neck-pain.nvim",
        version = vim.version.range("2.5.3"),
    },
    {
        src = "https://github.com/stevearc/oil.nvim",
        version = vim.version.range("2.16.0"),
    },

    {
        src = "https://github.com/nvim-mini/mini.nvim",
        version = vim.version.range("0.17.0"),
    },

    -- ===========================================================================
    -- LSP Completion / Formatting
    -- ===========================================================================
    {
        src = "https://github.com/stevearc/conform.nvim",
        version = vim.version.range("9.1.0"),
    },

    {
        src = "https://github.com/Saghen/blink.cmp",
        version = vim.version.range("1.10.2"),
    },
    {
        src = "https://github.com/supermaven-inc/supermaven-nvim.git",
        version = "main",
    },

    -- ===========================================================================
    -- Navigation
    -- ===========================================================================
    {
        src = "file:////home/macke/dev/home/github.com/ThePrimeagen/harpoon",
        version = "harpoon2",
    }, -- Should point to local!

    -- ===========================================================================
    -- Pickers / Search
    -- ===========================================================================
    -- Search is split by responsibility:
    --
    -- - fff.nvim owns file/content workflows:
    --   file search, live grep, and git/path-constrained file queries.
    --
    -- - fzf-lua owns generic picker workflows:
    --   vim.ui.select, help tags, LSP pickers, and custom selection actions.
    --
    -- fff has a picker UI, but it is not a generic picker API. Its UI is coupled
    -- to fff file/grep results, so fzf-lua remains intentional until those
    -- workflows move to native/quickfix flows or fff grows a `pick(items)` API.
    --
    -- Migration notes: docs/fzf-fff-migration.md

    { src = "https://github.com/ibhagwan/fzf-lua", version = "main" },
    { src = "https://github.com/dmtrKovalenko/fff.nvim", version = vim.version.range("0.9.4") },

    -- ===========================================================================
    -- Uncategorized
    -- ===========================================================================
    { src = "https://github.com/andymass/vim-matchup" },
    { src = "https://github.com/tpope/vim-sleuth" },
}, {
    load = false,
    confirm = false,
})
