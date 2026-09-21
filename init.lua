--[[
nvim-m Configuration Architecture
=================================

Personal configuration designed for minimal startup complexity while maintaining
full functionality. The approach is intentionally simple: load what's needed
immediately, then stagger everything else with short delays so the UI can render.

Design Principles
-----------------

1. Perceived Startup Speed
   The UI must appear instantly. I need to be able to jump into the editor
   and start working while heavy features load in the background. Total
   initialization time doesn't matter as much as perceived responsiveness.

2. Critical Path Only
   Only essential UI components load synchronously: options, keymaps, colorscheme,
   and basic autocommands. Everything else waits. This avoids lazy loading
   complexity while still achieving fast perceived startup.

3. Simple Staggered Loading
   Load the critical path immediately, then defer heavier modules file by file
   with a 2ms delay. No complex dependency management or conditional loading.
   If something is too slow, I'll replace it rather than add more complexity.

4. Observable Failures
   Everything is logged with timing. If something breaks, I can check the log
   buffer and see exactly what failed and how long each module took to load.

What Loads When
---------------

Immediate (synchronous):
- UI enhancements and theme - must be visible instantly
- Core options and keymaps - basic editing must work
- Language configs - syntax highlighting should be present
- Essential autocommands - only global ones, plugin-specific stay with plugins

Deferred (2ms delay):
- Everything else that is not needed within the first ~0.5 second of opening the editor

Performance Targets
-------------------


- Critical path: <15ms (UI visible and responsive)
- Total initialization: <100ms (background, doesn't block me)

The deferred phase uses a short delay between files. This gives the UI time to
render after the critical path while the rest of the setup continues in the
background.

If any module in the critical path exceeds performance targets, it gets replaced
with a faster alternative. I prioritize speed over feature completeness.

--]]

vim.loader.enable()

-- UI Enhancement - must load first
--
-- vim._core.ui2 affects the rendering pipeline. Loading it first prevents
-- visual artifacts and ensures consistent UI behavior.
require("vim._core.ui2").enable({})

-- Ensure that configuration-owned tools are only available to this Neovim instance.
local tools = vim.fs.joinpath(vim.fn.stdpath("config"), "tools")
local tool_paths = {
    vim.fs.joinpath(tools, "bin"),
    vim.fs.joinpath(tools, "lsp", "node_modules", ".bin"),
}
for index = #tool_paths, 1, -1 do
    local path = tool_paths[index]
    if vim.fn.isdirectory(path) == 1 then vim.env.PATH = path .. ":" .. (vim.env.PATH or "") end
end

local function runtime(path) return vim.api.nvim_get_runtime_file(path, true) end

require("aru.startup").load({
    critical = {
        -- Install plugins and add them to the runtime path before requiring
        -- plugin modules.
        { name = "packages", paths = runtime("lua/aru/pack.lua") },

        -- Restore sessions before the rest of the editor behavior starts.
        { name = "sessions", paths = runtime("lua/aru/plugins/continue.lua") },

        -- Register shared LSP behavior before language modules enable servers.
        { name = "lsp", paths = runtime("lua/aru/plugins/lsp.lua") },

        -- Language modules are independent and lightweight.
        { name = "languages", paths = runtime("lua/aru/languages/*.lua") },

        -- Core order is explicit because options and theme establish state read
        -- by later UI and behavior modules.
        { name = "options", paths = runtime("lua/aru/core/options.lua") },
        { name = "theme", paths = runtime("lua/aru/core/themes.lua") },
        { name = "spell", paths = runtime("lua/aru/core/spell.lua") },
        { name = "autosave", paths = runtime("lua/aru/autosave.lua") },
        { name = "autocommands", paths = runtime("lua/aru/core/autocommands.lua") },
        { name = "statusline", paths = runtime("lua/aru/core/statusline.lua") },
        { name = "keymaps", paths = runtime("lua/aru/core/keymaps.lua") },
    },
    deferred = {
        -- Deferred feature order is deliberate; no critical module is repeated.
        { name = "internal features", paths = runtime("lua/aru/setup.lua") },
        { name = "mini.nvim", paths = runtime("lua/aru/plugins/mini.lua") },
        { name = "blink.cmp", paths = runtime("lua/aru/plugins/blink.lua") },
        { name = "formatting", paths = runtime("lua/aru/plugins/conform.lua") },
        { name = "file search", paths = runtime("lua/aru/plugins/fff.lua") },
        { name = "git signs", paths = runtime("lua/aru/plugins/gitsigns.lua") },
        { name = "indent guides", paths = runtime("lua/aru/plugins/indent-blankline.lua") },
        { name = "centered layout", paths = runtime("lua/aru/plugins/no-neck-pain.lua") },
        { name = "file explorer", paths = runtime("lua/aru/plugins/oil.lua") },
        { name = "sqlite", paths = runtime("lua/aru/plugins/sqlite.lua") },
    },
})
