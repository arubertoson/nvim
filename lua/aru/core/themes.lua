local log = require("aru.log")
local theme = require("aru.custom").theme

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
            -- Spell (plain underline so it works without undercurl support)
            -- TODO: Revisit undercurl when the active terminal/UI path renders it
            -- reliably. Colored plain underline may ignore `sp` and use the text
            -- foreground color, but it is currently more visible than undercurl.
            ------------------------------------------------------------------
            SpellBad = { underline = true, sp = t.syn.diag_error },
            SpellCap = { underline = true, sp = t.syn.diag_warn },
            SpellLocal = { underline = true, sp = t.syn.diag_info },
            SpellRare = { underline = true, sp = t.ui.nontext },

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

-- TODO: Keep this override in sync with the spell module note. This forces plain
-- underline after colorscheme load because the colorscheme otherwise resolves
-- spell groups to undercurl, which does not render reliably in the current setup.
local function set_spell_underlines()
    local function diagnostic_fg(group)
        return vim.api.nvim_get_hl(0, { name = group, link = false }).fg
    end

    vim.api.nvim_set_hl(0, "SpellBad", {
        underline = true,
        cterm = { underline = true },
        sp = diagnostic_fg("DiagnosticError"),
    })
    vim.api.nvim_set_hl(0, "SpellCap", {
        underline = true,
        cterm = { underline = true },
        sp = diagnostic_fg("DiagnosticWarn"),
    })
    vim.api.nvim_set_hl(0, "SpellLocal", {
        underline = true,
        cterm = { underline = true },
        sp = diagnostic_fg("DiagnosticInfo"),
    })
    vim.api.nvim_set_hl(0, "SpellRare", {
        underline = true,
        cterm = { underline = true },
        sp = diagnostic_fg("Comment"),
    })
end

set_spell_underlines()

vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("aru_spell_highlights", { clear = true }),
    desc = "Use underline for spelling highlights",
    callback = set_spell_underlines,
})

log:debug("Activating theme: " .. theme)
vim.cmd.colorscheme(theme)
