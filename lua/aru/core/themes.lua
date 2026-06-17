local log = require("aru.log")
local theme = require("aru.custom").theme
local color = require("aru.colors")

require("kanagawa").setup({
    theme = "dragon", -- or "dragon"/"lotus"
    transparent = false,
    dimInactive = false,

    -- Nudge the theme primitives so “sidebar/gutter/popup” aren’t off
    colors = {
        theme = {
            all = {
                ui = {
                    bg_gutter = "none", -- same bg for signcolumn/line numbers as Normal
                    -- If you want popups to fully match Normal:
                    -- bg_p1 = "none",   -- popup base
                    -- bg_p2 = "none",   -- popup subtle layer
                },
            },
        },
    },

    overrides = function(colors)
        local t = colors.theme
        return {
            ------------------------------------------------------------------
            -- Sidebars
            ------------------------------------------------------------------
            -- Built-in “sidebar” group many UIs link to
            NormalSB = { fg = t.ui.fg, bg = t.ui.bg },

            ------------------------------------------------------------------
            -- Statusline / Winbar (blend in, not a neon runway)
            ------------------------------------------------------------------
            StatusLine = { fg = t.ui.fg, bg = t.ui.bg },
            StatusLineComment = { link = "Comment" },
            StatusLineNC = { fg = t.ui.nontext, bg = t.ui.bg },
            WinBar = { fg = t.ui.fg, bg = t.ui.bg },
            WinBarNC = { fg = t.ui.nontext, bg = t.ui.bg },

            ------------------------------------------------------------------
            -- Popups / Floats / Menus
            ------------------------------------------------------------------
            -- Hover/signature/help/etc.
            NormalFloat = { fg = t.ui.fg, bg = t.ui.bg }, -- same as editor
            FloatBorder = { fg = t.ui.nontext, bg = t.ui.bg }, -- soft border
            FloatTitle = { fg = t.syn.special1, bg = t.ui.bg, bold = true },
            BlinkCmpMenuBorder = { link = "FloatBorder" },

            -- Completion menu (nvim-cmp / wildmenu)
            Pmenu = { fg = t.ui.shade0, bg = t.ui.bg },
            PmenuSel = { fg = t.ui.shade0, bg = t.ui.bg_m2, bold = true },
            PmenuSbar = { bg = t.ui.bg_m1 },
            PmenuThumb = { bg = t.ui.bg_p2 },

            -- Telescope, if you use it
            TelescopeNormal = { bg = t.ui.bg },
            TelescopeBorder = { fg = t.ui.nontext, bg = t.ui.bg },

            ------------------------------------------------------------------
            -- Spell (undercurl misspellings)
            ------------------------------------------------------------------
            SpellBad = { undercurl = true, sp = t.syn.diag_error, fg = "none" },
            SpellCap = { undercurl = true, sp = t.syn.diag_warn, fg = "none" },
            SpellLocal = { undercurl = true, sp = t.syn.diag_info, fg = "none" },
            Rare = { undercurl = true, sp = t.ui.nontext, fg = "none" },

            ------------------------------------------------------------------
            -- Housekeeping so nothing sticks out
            ------------------------------------------------------------------
            SignColumn = { bg = t.ui.bg },
            LineNr = { fg = t.ui.nontext, bg = t.ui.bg },
            CursorLine = { bg = t.ui.bg_m3 }, -- subtle, optional
            VertSplit = { fg = t.ui.bg_m3, bg = t.ui.bg },
        }
    end,
})

vim.cmd.colorscheme("kanagawa") -- or kanagawa-wave/dragon/lotus

local function kanagawa_paper()
    require("kanagawa-paper").setup({
        lazy = false,
        priority = 1000,
        opts = {
            overrides = function()
                return {
                    LspInlayHint = {
                        fg = "#54546D",
                        bg = "None",
                        italic = true,
                    },
                    StatusLine = { link = "Normal" },
                }
            end,
            dim_inactive = true,
        },
    })
end

local function kanso()
    require("kanso").setup({
        bold = true, -- enable bold fonts
        italics = true, -- enable italics
        compile = false, -- enable compiling the colorscheme
        undercurl = true, -- enable undercurls
        commentStyle = { italic = true },
        functionStyle = {},
        keywordStyle = { italic = true },
        statementStyle = {},
        typeStyle = {},
        transparent = false, -- do not set background color
        dimInactive = false, -- dim inactive window `:h hl-NormalNC`
        terminalColors = true, -- define vim.g.terminal_color_{0,17}
        colors = { -- add/modify theme and palette colors
            palette = {},
            theme = { zen = {}, pearl = {}, ink = {}, all = {} },
        },
        overrides = function(colors) -- add/modify highlights
            return {}
        end,
        background = { -- map the value of 'background' option to a theme
            dark = "ink", -- try "zen", "mist" or "pearl" !
            light = "ink", -- try "zen", "mist" or "pearl" !
        },
        foreground = "default", -- "default" or "saturated"
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup(
            "aru_kanso_theme_tweaks",
            { clear = true }
        ),
        pattern = "help",
        callback = function()
            local ok, normal =
                pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
            if not ok or type(normal) ~= "table" then
                log:error(
                    ("kanso: Failed to get Normal highlight group: %s"):format(
                        normal
                    )
                )
                return
            end

            local bg = color.shade_color(normal.bg, -0.25)
            vim.api.nvim_set_hl(0, "HelpNormal", { fg = normal.fg, bg = bg })

            vim.api.nvim_set_option_value(
                "winhighlight",
                "Normal:HelpNormal",
                { scope = "local" }
            )
        end,
    })
end

kanagawa_paper()
-- elseif vim.startswith(theme, "kanso") then
-- 	kanso()
-- end

log:debug("Activating theme: " .. theme)
vim.cmd.colorscheme(theme)
