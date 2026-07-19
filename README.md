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

## Why so few dependencies / plugins?

Every plugin is a commitment. It can break, slow things down, or conflict with
something else. So I only add one when Neovim can't do it natively or the
plugin does it *significantly* better.

Dependencies need to earn its place. If a native feature catches up, the
plugin gets replaced, not stacked on top.

## Development

With `mise` and `just` available, bootstrap a fresh checkout with:

```sh
just setup
```

This installs the configuration-owned StyLua and LuaLS versions, the Node-based
tools declared in `tools/lsp/package.json`, Neovim plugins, and the pre-commit hook.
It then runs the complete quality gate. Neovim, Node, Mise, and Just are system
prerequisites; language tooling for target repositories remains target-repository-owned.
Every commit reruns `just check`, which verifies Lua formatting and runs the test suite.
Use `just format` to fix formatting failures.

## Feature documentation

- [Agent interaction](docs/agent-interaction.md)
