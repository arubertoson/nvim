# Native Logging Migration

## Status

Proposed.

## Objective

Replace the custom logging implementation with Neovim 0.13's file-backed
`vim.log` API. Keep logging for diagnostics and make user-facing notifications
explicit at the call site.

The migration should remove infrastructure that is no longer needed without
recreating sink routing around the native API.

## Required Neovim version

Neovim 0.13 or newer is required. Supporting older versions or providing a
logging fallback is out of scope.

## Current state

`lua/aru/log.lua` owns:

- file, buffer, and notification sinks;
- per-sink levels and fan-out;
- file creation, buffering, flushing, and cleanup;
- deferred buffer writes around fast events and textlock;
- timestamp, process ID, module, and line formatting;
- bound child loggers;
- printf-style log arguments; and
- global logger configuration.

Normal startup configures a debug-level file sink at
`stdpath("cache")/nvim-config.log`. After deferred startup completes, a
notification sink is attached for `INFO` and higher messages. The buffer sink
is not used by the normal configuration.

## Target state

### Logger ownership

`lua/aru/log.lua` remains only as the configuration-owned access point and
returns one native logger:

```lua
return vim.log.new({
    name = "aru",
    level = vim.log.levels.DEBUG,
})
```

Requiring `aru.log` must always return the same logger through Lua's module
cache. No custom `Logger` class, sink abstraction, lifecycle management, or
compatibility facade remains.

The resulting log is owned by Neovim and stored as `aru.log` under
`stdpath("log")`, currently `stdpath("state")/logs`.

### Calling convention

All call sites use the native dot-call API:

```lua
local log = require("aru.log")

log.debug("buffer pruned", { path = path })
log.error("request failed", err)
```

The migration must:

- replace `log:debug(...)`, `log:info(...)`, and equivalent colon calls;
- remove `bind()` calls;
- stop using printf placeholders as a logging API;
- pass useful values as additional native logger arguments, or format a message
  before passing it when prose requires interpolation; and
- replace direct invalid calls such as `vim.log.error(...)` with the configured
  `aru.log` instance.

Native source path and line metadata replace bound module labels. The default
native formatter replaces the custom timestamp, PID, and format template.

### Logs versus notifications

A log records diagnostic information. A notification communicates an outcome
that requires the user's attention. Logging a message must not implicitly
notify the user.

Remove the notification sink and `attach_notify_sink()`. Audit affected call
sites and use `vim.notify()` explicitly only when the message is actionable or
represents an expected interactive outcome. In particular:

- retain the existing aggregated notification for deferred startup failures;
- notify for interactive outcomes such as no diagnostic at the cursor or no
  response available to restore, if those actions otherwise provide no visible
  feedback;
- notify for runtime failures only when the initiating operation does not
  already display the failure in its UI; and
- keep internal state, plugin-load, watcher, timing, and troubleshooting details
  in the log only.

A failure may be both logged and notified when the log contains diagnostic
context and the notification gives the user a concise actionable message.

### Inspection

Use Neovim's native command to inspect the configuration log:

```vim
:log aru
```

Remove the keymap that opens `stdpath("cache")/nvim-config.log` directly. Do not
add another file-path-aware log viewer. If a convenience keymap is retained in
a later change, it must invoke `:log aru` rather than construct a path.

Remove the obsolete `nvim-config.log` entry from `.gitignore`.

## Implementation scope

1. Reduce `lua/aru/log.lua` to creation and return of the native logger.
2. Remove custom logger configuration from `init.lua`.
3. Remove notification-sink attachment from `lua/aru/startup.lua`.
4. Convert every `aru.log` call site to the native dot-call API.
5. Remove bound logger creation and rely on native source metadata.
6. Separate implicit notifications into explicit `vim.notify()` calls where
   justified by the interaction rules above.
7. Replace the direct log-file inspection keymap with native `:log` usage by
   removing the keymap.
8. Remove obsolete log-file ignore configuration.
9. Update tests that configure or depend on the custom logger.

## Out of scope

- Reintroducing buffer or notification sinks around `vim.log`.
- Supporting arbitrary log paths.
- Preserving the exact historical output format.
- Preserving PID or millisecond timestamp fields.
- Preserving one log level per destination.
- Supporting Neovim 0.12 or older.
- Migrating plugin-owned logs into `aru.log`.
- Log rotation or retention beyond Neovim's behavior.

## Acceptance criteria

- `lua/aru/log.lua` contains no custom sink, queue, formatter, file-handle, or
  logger-class implementation.
- `require("aru.log")` returns a `vim.Log` configured as `aru` at `DEBUG` level.
- No call site uses `bind()`, `configure()`, `add()`, or colon-call logger
  methods.
- No call site treats `vim.log` itself as a logger instance.
- Logging never produces a notification as a side effect.
- Interactive operations that require feedback still notify explicitly.
- `:log aru` opens the configuration log.
- New entries contain their native level and source location.
- Debug messages are recorded; trace messages are filtered by default.
- Startup and asynchronous callbacks can log without writing to Neovim buffers.
- The old `nvim-config.log` path is no longer referenced.
- Lua formatting and the complete test suite pass via `just check`.

## Manual verification

1. Start Neovim and execute code paths that emit debug, info, warning, and error
   records.
2. Run `:log aru` and confirm the records include levels and source locations.
3. Confirm trace-level startup timing records are absent at the configured
   `DEBUG` threshold.
4. Trigger an interactive no-result outcome and confirm it produces the intended
   explicit notification.
5. Trigger a diagnostic-only log entry and confirm it does not notify.
6. Confirm no `nvim-config.log` file is created under `stdpath("cache")`.
