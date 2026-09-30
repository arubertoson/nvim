# 🐉 here be dragons -- aru's nvim config

> **Disclaimer:** This is my personal Neovim configuration. It's built around
> how I work, on the machines I use, for the languages I write. It will most
> likely not work out of the box for you, and that's fine. It's mine, and I
> like it.

## How it loads

No third-party plugin manager. Plugins are installed with Neovim's built-in
package manager. Everything loads in two chunks:

1. **Now** - UI, options, keymaps, colorscheme, sessions. You see the editor
   immediately.
2. **2ms later** - everything else, staggered in the background so the UI never
   stutters.

No lazy loading. No event-based triggers. No dependency graphs. If something is
too slow, I replace it. I don't add complexity to work around it.

## Architecture

The configuration is organized by editor behavior, not by plugin:

- `runtime/` owns package loading and startup phases.
- `editor/` owns universal editing policy and text-editing assistance.
- `interface/` owns presentation and temporary-window behavior.
- `language/` owns language tooling; `servers/` is its only nested family.
- `workspace/` owns project navigation, files, Git, sessions, and layout.
- `tools/` owns standalone workflows such as Psst and Lua Scratch.

A behavior owns its setup, lifecycle, and mappings. Plugins are implementation
details within those modules; there are no forwarding plugin-config files. A
new directory must represent a real family of behaviors, not contain a single
wrapper file.

## Why so few dependencies / plugins?

Every plugin is a commitment. It can break, slow things down, or conflict with
something else. So I only add one when Neovim can't do it natively or the
plugin does it *significantly* better.

Dependencies need to earn its place. If a native feature catches up, the
plugin gets replaced, not stacked on top.

## TypeScript

The configuration chooses one TypeScript server per project:

- Installed project TypeScript 6 or older uses `ts_ls` and its own `tsserver.js`.
- Installed project TypeScript 7 or newer uses its native LSP (`tsc --lsp --stdio`).
- Without project TypeScript, the native installation in `tools/lsp` is used.

Selection is kept for the Neovim session. Install a project version and restart
Neovim when you need different behavior. Deno projects are excluded from both
servers. The legacy `LspTypescript*` commands remain specific to `ts_ls`; standard
LSP navigation and code actions work with either server.

## Development

With `mise` and `just` available, bootstrap a fresh checkout with:

```sh
just setup
```

This installs the configuration-owned StyLua and LuaLS versions, the Node-based
tools declared in `tools/lsp/package.json`, Neovim plugins, and the pre-commit hook.
It then runs the complete quality gate. Neovim, Node, Mise, and Just are system
prerequisites; language tooling for target repositories remains target-repository-owned.
`just test-tools-install` installs the isolated legacy TypeScript fixture for
integration tests against both real server backends; `just setup` includes it.
Every commit reruns `just check`, which verifies Lua formatting and runs the test suite.
Use `just format` to fix formatting failures.
