# fzf-lua to fff migration

## Decision

Use fff for file/content interaction and mini.pick/mini.extra for generic picker workflows.

fff is a good replacement for file search and live grep, but not for arbitrary item pickers. Its picker UI is file/grep-specific:

- normal mode searches through fff's file index
- grep mode searches through fff's content backend
- selection expects a file item with `relative_path` and opens it

Generic LSP, diagnostics, and code-action interactions now use mini.pick/mini.extra instead of fzf-lua. fff is intentionally not used for these because it is file/grep-specific.

## Completed migration

1. Move file/content mappings to fff. The mappings live in `lua/aru/plugins/fff.lua` so config and plugin-specific keys load together.
   - `<leader>ff`: `require("fff").find_files({ cwd = vim.uv.cwd() })`
   - `<leader>fs`: `require("fff").live_grep({ cwd = vim.uv.cwd() })`
   - `<leader>fc`: `require("fff").find_files({ cwd = vim.uv.cwd(), query = "git:modified " })`

2. Remove current-buffer grep.
   - Previous fzf-lua usage: `lgrep_curbuf()`.
   - fff has no direct current-buffer grep picker.
   - Do not keep a weak replacement just to preserve the mapping.

3. Add a lightweight generic picker layer.
   - `mini.pick` provides the picker UI and `vim.ui.select` implementation
   - `mini.extra` provides LSP and diagnostic pickers
   - help lookup still uses `:help` command-line completion
   - code actions use `vim.lsp.buf.code_action()` through the `vim.ui.select` override

4. Remove fzf-lua.
   - removed package spec
   - removed plugin config
   - removed lockfile entry

## Follow-up: diagnostic copy UX

The important remaining UX is copying diagnostics for use elsewhere. Prefer explicit diagnostic helpers over going back to quickfix/location-list as the primary diagnostic UI.

Potential helpers:

- copy current diagnostic
- copy all current-buffer diagnostics
- copy workspace diagnostics

## Exit criteria

fzf-lua is removed when all of these remain true:

- no `require("fzf-lua")` calls remain
- no package spec or lockfile entry remains
- `vim.ui.select` uses `mini.pick`
- help lookup through `:help` is acceptable
- LSP and diagnostic workflows use searchable `mini.extra` pickers
- fff covers all file/content search mappings
