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

require("aru.runtime.startup").load({
    critical = {
        -- Packages must be on the runtime path before behavior is configured.
        { name = "packages", paths = runtime("lua/aru/runtime/packages.lua") },
        { name = "sessions", paths = runtime("lua/aru/workspace/sessions.lua") },

        -- Shared LSP policy precedes independent server declarations.
        { name = "language behavior", setup = function() require("aru.language.lsp").setup() end },
        { name = "language servers", paths = runtime("lua/aru/language/servers/*.lua") },

        -- Editor policy establishes state read by interface and workspace behavior.
        { name = "editor options", paths = runtime("lua/aru/editor/options.lua") },
        { name = "theme", paths = runtime("lua/aru/interface/theme.lua") },
        { name = "spell", paths = runtime("lua/aru/editor/spell.lua") },
        { name = "autosave", paths = runtime("lua/aru/editor/autosave.lua") },
        { name = "editor events", paths = runtime("lua/aru/editor/events.lua") },
        { name = "statusline", paths = runtime("lua/aru/interface/statusline.lua") },
        { name = "editor keymaps", paths = runtime("lua/aru/editor/keymaps.lua") },
    },
    deferred = {
        { name = "workspace navigation", paths = runtime("lua/aru/workspace/navigation.lua") },
        { name = "text editing", paths = runtime("lua/aru/editor/text.lua") },
        { name = "notifications", paths = runtime("lua/aru/interface/notifications.lua") },
        { name = "picker", paths = runtime("lua/aru/interface/picker.lua") },
        { name = "completion", paths = runtime("lua/aru/language/completion.lua") },
        { name = "formatting", paths = runtime("lua/aru/language/formatting.lua") },
        { name = "file search", paths = runtime("lua/aru/workspace/search.lua") },
        { name = "Git signs", paths = runtime("lua/aru/workspace/git_signs.lua") },
        { name = "indent guides", paths = runtime("lua/aru/editor/indent.lua") },
        { name = "centered layout", paths = runtime("lua/aru/workspace/layout.lua") },
        { name = "file explorer", setup = function() require("aru.workspace.files").setup() end },
        { name = "Psst", paths = runtime("lua/aru/tools/psst.lua") },
        { name = "SQLite scratch", setup = function() require("sqlite-scratch").setup() end },
        { name = "Lua scratch", setup = function() require("aru.tools.lua_scratch").setup() end },
    },
})
