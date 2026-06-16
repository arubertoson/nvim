# fzf-lua to fff migration

## Decision

Use fff for file/content interaction. Keep fzf-lua for generic picker workflows until they are replaced by native/quickfix flows or fff exposes a public generic picker API.

fff has a picker UI, but it is file/grep-specific today:

- normal mode searches through fff's file index
- grep mode searches through fff's content backend
- selection expects a file item with `relative_path` and opens it

That makes fff a good replacement for file search and live grep, but not for arbitrary item pickers like help tags, LSP symbols, code actions, or `vim.ui.select`.

## Migration plan

1. Move file/content mappings to fff. Done.
   - `<leader>ff`: `require("fff").find_files({ cwd = vim.uv.cwd() })`
   - `<leader>fs`: `require("fff").live_grep({ cwd = vim.uv.cwd() })`
   - `<leader>fc`: `require("fff").find_files({ cwd = vim.uv.cwd(), query = "git:modified " })`

2. Remove current-buffer grep. Done.
   - Previous fzf-lua usage: `lgrep_curbuf()`.
   - fff has no direct current-buffer grep picker.
   - Do not keep a weak replacement just to preserve the mapping.

3. Keep fzf-lua for generic picker responsibilities.
   - `fzf.register_ui_select()`
   - `help_tags()`
   - LSP document/workspace symbols
   - LSP diagnostics
   - LSP definitions/references/implementations/type definitions
   - LSP code actions
   - custom copy-selection actions

4. Reduce LSP picker dependence only if the replacement is better.
   - Prefer native LSP jumps for single-target actions.
   - Prefer quickfix/location-list for multi-target actions.
   - Do not force these through fff unless fff adds a generic picker API.

5. Remove fzf-lua only when no generic picker use remains.
   - Either all generic workflows moved to native/quickfix flows, or another small generic picker replaces fzf-lua.
   - Until then, fzf-lua is intentionally retained and should not be considered dead dependency weight.

## Exit criteria

fzf-lua can be removed when all of these are true:

- no `require("fzf-lua")` calls remain outside its plugin config
- `vim.ui.select` has an acceptable replacement or default UI is acceptable
- help tag lookup has an acceptable replacement
- LSP picker workflows have moved to native/quickfix/location-list flows
- fff covers all file/content search mappings
