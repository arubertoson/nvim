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
    -- Pickers / Search
    -- ===========================================================================
    -- fff.nvim owns file/content workflows: file search, live grep, and
    -- git/path-constrained file queries.
    --
    -- fff stays focused on file/content search. mini.pick/mini.extra provides
    -- the generic searchable picker layer for LSP, diagnostics, and vim.ui.select
    -- flows such as code actions.
    --
    -- Migration notes: docs/fzf-fff-migration.md

    { src = "https://github.com/dmtrKovalenko/fff.nvim", version = vim.version.range("0.9.4") },

    -- ===========================================================================
    -- Uncategorized
    -- ===========================================================================
    { src = "https://github.com/tpope/vim-sleuth" },
    { src = "https://github.com/OXY2DEV/markview.nvim" },

}, {
    load = false,
    confirm = false,
})

local function pack_names(filter)
    return vim.iter(vim.pack.get())
        :filter(filter)
        :map(function(x) return x.spec.name end)
        :totable()
end

vim.api.nvim_create_user_command("PackUpdate", function(opts)
    local names = #opts.fargs > 0 and opts.fargs or pack_names(function(x) return x.active end)

    if vim.tbl_isempty(names) then
        vim.notify("No active packages to update", vim.log.levels.INFO, { title = "vim.pack" })
        return
    end

    vim.pack.update(names, { force = opts.bang })
end, {
    bang = true,
    nargs = "*",
    complete = function() return pack_names(function(x) return x.active end) end,
    desc = "Update active vim.pack packages; use ! to skip confirmation",
})

vim.api.nvim_create_user_command("PackClean", function()
    local inactive = pack_names(function(x) return not x.active end)

    if vim.tbl_isempty(inactive) then
        vim.notify("No inactive packages to clean", vim.log.levels.INFO, { title = "vim.pack" })
        return
    end

    vim.pack.del(inactive)
end, { desc = "Delete inactive vim.pack packages" })
