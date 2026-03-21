local custom = require("aru.custom")
local blink = require("blink.cmp")

blink.setup({
    fuzzy = { implementation = "prefer_rust_with_warning" },
    appearance = { kind_icons = custom.icons.kind },

    -- We activate completion sources for specific actions on the cmdline
    cmdline = {
        sources = function()
            local t = vim.fn.getcmdtype()
            if t == "/" or t == "?" then return { "buffer" } end
            if t == ":" then return { "cmdline" } end
            return {}
        end,
    },

    completion = {
        accept = { auto_brackets = { enabled = true } },
        trigger = {
            show_on_insert = false,
            show_on_trigger_character = true,
        },
        documentation = {
            auto_show = true,
            auto_show_delay_ms = 150,
            update_delay_ms = 120,
            treesitter_highlighting = true,
            window = { border = "rounded", winblend = vim.o.pumblend },
        },
        ghost_text = { enabled = false, show_with_menu = false },
        list = {
            selection = {
                preselect = function(ctx)
                    return ctx.mode ~= "cmdline"
                        and not require("blink.cmp").snippet_active({
                            direction = 1,
                        })
                end,
            },
        },
        menu = {
            auto_show = function(ctx) return ctx.mode ~= "default" end,
            border = "rounded",
            -- Minimum width should be controlled by components
            min_width = 1,
            draw = {
                columns = {
                    { "kind_icon" },
                    { "label", "label_description", gap = 1 },
                    { "provider" },
                },
                components = {
                    provider = {
                        text = function(ctx)
                            return "["
                                .. ctx.item.source_name:sub(1, 3):upper()
                                .. "]"
                        end,
                    },
                },
            },
        },
    },

    sources = {
        default = { "lsp", "path", "snippets", "buffer" }, -- , "lazydev" },
        providers = {
            -- lsp = { min_keyword_length = 2, name = "LSP", fallbacks = { "lazydev" } },
            -- path = { min_keyword_length = 0 },
            -- snippets = { min_keyword_length = 1 },
            buffer = { min_keyword_length = 3, max_items = 5 },
            -- lazydev = { name = "Development", module = "lazydev.integrations.blink" },
        },
    },

    signature = {
        enabled = true,
        window = {
            show_documentation = true,
            border = "rounded",
            winblend = vim.o.pumblend,
        },
    },

    keymap = {
        preset = "none",

        ["<C-p>"] = { "select_prev", "fallback" },
        ["<C-n>"] = { "select_next", "fallback" },

        ["<C-u>"] = { "scroll_documentation_up", "fallback" },
        ["<C-d>"] = { "scroll_documentation_down", "fallback" },
        ["<C-e>"] = { "hide" },
    },
})
