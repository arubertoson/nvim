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

-- Core infrastructure - timing and loading utilities
require("aru.log").configure({
    sinks = {
        {
            type = "file",
            path = vim.fs.joinpath(vim.fn.stdpath("cache"), "nvim-config.log"),
            level = vim.log.levels.DEBUG,
        },
    },
})

-- Ensure that we have a clean tools directory only available for our nvim instance.
local lsp_bin = vim.fs.joinpath(vim.fn.stdpath("config"), "tools", "lsp", "node_modules", ".bin")
if vim.fn.isdirectory(lsp_bin) == 1 then vim.env.PATH = lsp_bin .. ":" .. (vim.env.PATH or "") end

require("aru.startup").load({
    -- Install and add plugins to the runtime path before we start working
    -- on other parts of the setup. This should be a fairly fast setup as
    -- we are only adding the lua modules to the runtimepath and making
    -- them available to require.
    vim.api.nvim_get_runtime_file("lua/aru/pack.lua", true),

    -- Second thing to load is sessions, these should be restored before we
    -- start loading deferred functionality.
    vim.api.nvim_get_runtime_file("lua/aru/plugins/continue.lua", true),

    -- We set up the lsp and language configs, these are lightweight and
    -- should be loaded early as it can impact general file behavior.
    vim.api.nvim_get_runtime_file("lua/aru/languages/*.lua", true),

    -- Core modules - basic editor functionality; options, keymaps, and
    -- essential autocommands. Only the bare minimum goes here, everything
    -- else is deferred. Order is not important, we just want everything...
    vim.api.nvim_get_runtime_file("lua/aru/core/*.lua", true),
}, {
    -- Deferred loading, staggered to run one by one with a 2ms delay
    -- between each file. This allows the UI to render quick enough to
    -- be responsive while the rest of the setup is loading.
    vim.api.nvim_get_runtime_file("lua/aru/plugins/*.lua", true),
})
