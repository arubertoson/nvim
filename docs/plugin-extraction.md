# Plugin extraction process

This document governs extraction of configuration-owned features into standalone
Neovim plugins. The plugins remain personal software: they preserve the workflow
that motivated them instead of growing abstractions for hypothetical users.

## Publishing position

Each repository is public so its source can be inspected. It is not an open-source
project and grants no license to copy, modify, or redistribute the code. It has no
support, compatibility, contribution, or roadmap promise. The README should say
this directly and then document the software well enough for the author's future
self to install, operate, and debug it.

## Extraction workflow

Apply these phases to one plugin at a time. Finish and use each extracted plugin
before beginning the next one.

### 1. Fix the identity

Decide and record:

- repository name and Lua module namespace;
- one-sentence purpose;
- workflows the plugin owns;
- explicit non-goals;
- required and optional external dependencies.

A name is accepted only when it describes the actual workflow and does not imply a
more general product than the code provides.

### 2. Preserve behavior

Before moving code:

- identify the public entry point, commands, functions, mappings, events, buffer
  variables, and persisted data;
- identify every call site in this configuration;
- retain tests for each meaningful user workflow and lifecycle invariant;
- record current external executable and Neovim plugin requirements.

Extraction is not a redesign. Existing behavior remains the baseline unless a
repository-specific coupling must be removed.

### 3. Cut the boundary

Classify every dependency as one of:

- **owned:** move it into the plugin;
- **platform:** use the Neovim API directly;
- **required integration:** document it as a dependency;
- **personal policy:** keep it in this configuration and pass it through the
  smallest necessary plugin option or callback;
- **false generalization:** delete it and implement the one behavior actually in
  use.

Do not extract a general-purpose utility library. Small buffer, path, logging,
Git-scope, or Treesitter operations should live privately inside the plugin that
needs them.

### 4. Build the standalone repository

Create the plugin beside this configuration with:

- `lua/<namespace>/` and a single public entry point;
- `README.md` with status, purpose, requirements, installation, configuration,
  usage, non-goals, and development instructions;
- an explicit all-rights-reserved notice;
- standalone formatting and test commands;
- tests moved with production behavior;
- health checks when the plugin depends on external executables.

Rename internal modules, augroups, namespaces, events, buffer variables, filetypes,
and persisted paths. No standalone plugin may require an `aru.*` module.

### 5. Swap the integration

Only after standalone tests pass:

1. add the repository to `vim.pack.add`;
2. update this configuration's setup, keymaps, completion integration, callbacks,
   and type references to the new namespace;
3. run the configuration against the installed plugin;
4. remove the original production files and migrated tests in the same change.

There is no compatibility shim: this configuration and the plugin move together.

### 6. Verify the cut

The extraction is complete when:

- the standalone plugin's formatting and tests pass;
- this configuration's focused tests and complete `just check` pass;
- a headless startup can require and set up the plugin;
- relevant health checks pass or report missing external tools accurately;
- searching the configuration finds no old module namespace or copied production
  implementation;
- the plugin repository contains no dependency on this configuration.

### 7. Publish and soak

Commit and publish the plugin, pin or lock it in this configuration, and use it in
normal editing before extracting the next plugin. Fix extraction regressions in the
plugin repository, not by restoring local copies.

## Completed extractions

### [`sqlite-scratch.nvim`](https://github.com/arubertoson/sqlite-scratch.nvim)

**Lua namespace:** `sqlite-scratch`
**Purpose:** a query-first SQLite scratchpad for writing, running, inspecting, and
revisiting SQL without leaving Neovim.

Owned behavior:

- `:SQLiteOpen`, `:SQLiteClose`, and `:SQLiteExport`;
- scratchpad tab, query buffer, result view, SQL preview, and execution history;
- bounded asynchronous `sqlite3` execution and CSV parsing;
- per-database `sqls` client and health diagnostics.

Dependencies: Neovim, `sqlite3`, and `sqls`. The plugin has no dependency on this
configuration.

Non-goals: other database engines, database administration, migration management,
unbounded result grids, and a public adapter framework.

### [`psst.nvim`](https://github.com/arubertoson/psst.nvim)

**Lua namespace:** `psst`

**Purpose:** a quick way to ask about the code while working: gather relevant editor
context, inspect a streamed answer beside the code, and optionally bring a generated
response back into the editor without breaking focus. Pi is the initial harness, not
the product boundary.

The name describes the interaction rather than the implementation: “psst, quick
question.” Its README should lead with that low-friction workflow and treat harness
adapters as supporting detail.

Owned behavior:

- prompt and inline-reference UI;
- file, symbol, diagnostic, selection, and semantic-block context collection;
- harness command construction and streaming response handling, initially for Pi;
- response/session history and read float;
- optional Blink completion sources for prompt references.

Dependencies: Neovim, a configured agent harness executable, Treesitter parsers,
and `nvim-treesitter-textobjects` queries for semantic block collection. Pi is the
only initial harness. Blink is an optional integration owned by this configuration.

Boundary changes:

- rename the current runtime concept to harness and isolate Pi command/event details
  in `adapters/pi.lua`;
- define only the adapter operations required by the existing Pi behavior; defer a
  generalized capability model until a second harness is implemented;
- replace shared `aru.log` and `aru.ts` dependencies with narrow private modules;
- rename all `aru` UI identifiers and default storage paths;
- keep the two real response destinations internal rather than exposing a destination
  extension framework.

Non-goals: implementing a coding agent, accepting arbitrary protocol plugins,
provider discovery, normalizing every harness feature, and ownership of global
keymaps.

### [`tracks.nvim`](https://github.com/arubertoson/tracks.nvim)

**Lua namespace:** `tracks`

**Purpose:** preserve semantic cursor landings and file visits while maintaining a
small branch-scoped working set of loaded files.

Owned behavior:

- semantic in-buffer point history;
- browser-like file visit history with restored views;
- persisted project-and-branch-scoped active-file slots;
- MRU buffer pruning with active files pinned.

Dependencies: Neovim, Git repositories for branch-scoped active files, Treesitter
parsers, and `nvim-treesitter-textobjects` queries for semantic points.

Boundary changes:

- replace `aru.buf` and `aru.quick_close` with one private file-buffer eligibility
  policy;
- move only synchronous project/branch scope detection from `aru.git`; do not move
  the unrelated branch watcher/cache;
- replace `aru.log` with plugin-local logging;
- move only the two Treesitter operations point history uses;
- replace the configuration-derived active-file count with a direct default;
- expose subsystem options through one setup boundary without adding adapters or
  extension registries.

Non-goals: replacing Neovim's jumplist, a general bookmark manager, a bufferline,
session management, or non-Git project detection.

## Execution order

1. `sqlite-scratch.nvim`
2. `psst.nvim`
3. `tracks.nvim`

All three extractions are published, locked through `vim.pack`, and consumed by this
configuration. Their production implementations and behavioral tests now live in the
plugin repositories.
