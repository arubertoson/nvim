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

local plugins = {}

local function add_personal_plugin(name)
    local dev_home = vim.env.XDG_DEV_HOME
    local local_path = dev_home
        and vim.fs.joinpath(dev_home, "home", "github.com", "arubertoson", name)

    if local_path and vim.fn.isdirectory(local_path) == 1 then
        vim.opt.runtimepath:prepend(local_path)
        return
    end

    plugins[#plugins + 1] = { src = "https://github.com/arubertoson/" .. name }
end

add_personal_plugin("psst.nvim")
add_personal_plugin("sqlite-scratch.nvim")
add_personal_plugin("tracks.nvim")

vim.list_extend(plugins, {
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
    -- ===========================================================================
    -- Pickers / Search
    -- ===========================================================================
    -- fff.nvim owns file/content workflows: file search, live grep, and
    -- git/path-constrained file queries.
    --
    -- fff stays focused on file/content search. mini.pick/mini.extra provides
    -- the generic searchable picker layer for LSP, diagnostics, and vim.ui.select
    -- flows such as code actions.
    --
    { src = "https://github.com/dmtrKovalenko/fff.nvim", version = "v0.9.6" },

    -- ===========================================================================
    -- Uncategorized
    -- ===========================================================================
    { src = "https://github.com/tpope/vim-sleuth" },
    { src = "https://github.com/OXY2DEV/markview.nvim" },
})

vim.pack.add(plugins, {
    load = false,
    confirm = false,
})
