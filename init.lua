--[[
nvim-m Configuration Architecture
=================================

Personal configuration designed for minimal startup complexity while maintaining
full functionality. The approach is intentionally simple: load what's needed
immediately, defer everything else. No lazy loading complexity, just chunked
loading with a short delay to let the UI render.

Design Principles
-----------------

1. Perceived Startup Speed
   The UI must appear instantly. I need to be able to jump into the editor
   and start working immediately while heavy features load in the background.
   Total initialization time doesn't matter as much as perceived responsiveness.

2. Critical Path Only
   Only essential UI components load synchronously: options, keymaps, colorscheme,
   and basic autocommands. Everything else waits. This avoids lazy loading
   complexity while still achieving fast perceived startup.

3. Simple Chunked Loading
   Load in two chunks: immediate (UI), deferred after 2ms (heavy features),
   and that's it. No complex dependency management or conditional loading.
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
- Everything else that is not neede within the first ~0.5 second of opening the editor

Performance Targets
-------------------


- Critical path: <15ms (UI visible and responsive)
- Total initialization: <100ms (background, doesn't block me)

We add a 2ms delay to the deferred loading, this allows the UI thread time to
render after the critical path is complete. Afterwards we can slowly stagger
the rest of the setup without blocking the UI.

If any module in the critical path exceeds performance targets, it gets replaced
with a faster alternative. I prioritize speed over feature completeness.

--]]

vim.loader.enable()

-- UI Enhancement - must load first
--
-- vim._extui affects the rendering pipeline. Loading it first prevents
-- visual artifacts and ensures consistent UI behavior.
require("vim._core.ui2").enable({})

-- Core infrastructure - timing and loading utilities
local log = require("aru.log").configure({
    level = vim.log.levels.TRACE,
    sinks = {
        {
            type = "file",
            path = "$XDG_CACHE_HOME/nvim/nvim-config.log",
            level = vim.log.levels.TRACE,
        },
    },
})
local startup = require("aru.startup")

-- Module loading with performance tracking
--
-- Everything is timed so I can see what's slow and replace it.
-- The split between immediate and deferred loading creates the illusion
-- of instant startup while still getting all features eventually.
local _, total_time = startup.timeit_ms(function()
    -- Immediate loading - critical path for UI responsiveness
    --
    -- These must load synchronously because I need them working immediately
    -- when the editor appears. The order matters for dependencies.
    local _, direct_load_time = startup.timeit_ms(function()
        startup.load_files({
            -- Install and add plugins to the runtime path before we start working
            -- on other parts of the setup. This should be a fairly fast setup as
            -- we are only adding the lua modules to the runtimepath and making
            -- them available to require.
            vim.api.nvim_get_runtime_file("lua/aru/pack.lua", true),

            -- Second thing to load is sessions, these should be restored before we
            -- start loading defered functionalities.
            vim.api.nvim_get_runtime_file("lua/aru/plugins/continue.lua", true),

            -- We setup the lsp and language configs, these are light weight and
            -- should be loaded early as it can impact general file behavior.
            vim.api.nvim_get_runtime_file("lua/aru/languages/*.lua", true),

            -- Core modules - basic editor functionality; options, keymaps, and
            -- essential autocommands. Only the bare minimum goes here, everything
            -- else is deferred. Order is not important, we just want everything...
            vim.api.nvim_get_runtime_file("lua/aru/core/*.lua", true),
        })
    end)
    log:trace(
        string.format("Critical path load time: %.3f ms", direct_load_time)
    )

    -- Deferred loading - plugins
    --
    -- These load after 2ms delay to let UI render first. At this point order is
    -- not important, we just want everything... eventually.
    local _, defer_load_time = startup.timeit_ms(
        function()
            startup.defer_load_files({
                vim.api.nvim_get_runtime_file("lua/aru/plugins/*.lua", true),
            }, 2)
        end
    )
    log:trace(string.format("defered load time: %.3f ms", defer_load_time))
end)

-- Performance summary
--
-- Total time excluding background loading. What I actually experience
-- is just the direct load time since deferred loading happens while
-- after the UI thread has finished loading.
log:trace(string.format("total load time: %.3f ms", total_time))

-- We add a notify sink after initial setup for any further runtime errors
-- that we can report. We avoid the notify sink for the startup path as it
-- can potentially produce a lot of noise.
vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        local ok, err = pcall(startup.flush_startup_errors)
        if not ok then
            vim.notify(
                "flush_startup_errors failed:\n" .. err,
                vim.log.levels.ERROR
            )
        end

        local ok, err = pcall(
            function()
                require("aru.log"):add({
                    type = "notify",
                    level = vim.log.levels.ERROR,
                })
            end
        )
        if not ok then
            vim.notify(
                "log notify sink attach failed:\n" .. err,
                vim.log.levels.ERROR
            )
        end
    end,
})
