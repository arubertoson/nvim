# Agent Interaction

A focused Neovim integration for sending editor context and user intent to an
agent. It provides three interaction paths without recreating an agent chat UI
inside Neovim.

## Concepts

- **Executable**: the concrete command or path, such as `pi-dev` or a local build.
- **Runtime**: the CLI and streaming protocol shared by compatible executables.
- **Destination**: where a handoff goes: the read Float, the Editor, or tmux.
- **Session policy**: whether a process starts, continues, or avoids a saved session.

The built-in `pi` runtime can be used with any compatible executable:

```lua
require("aru.agent").setup({
    executable = "pi-dev",
    runtime = "pi",
    target_window_name = "agent",
})
```

## Prompt

`<leader>p` opens a prompt using the current editor location. Normal mode captures
the cursor and surrounding block. Visual mode captures the selected range.

Inside the prompt:

| Key | Interaction |
| --- | --- |
| `<CR>` | Read, continuing the current session when available |
| `<C-CR>` | Read in a fresh session |
| `<C-g>` | Generate code in the Editor |
| `<C-p>` | Send to the active tmux agent session |
| `<C-j>` | Insert a prompt newline |
| `<Esc>` | Cancel |

## Read

Read streams the response into an upper-right Float without moving focus.

- The first request starts a saved session.
- Later requests automatically continue it while Neovim remembers a successful
  session for the current working directory.
- `<C-CR>` always starts fresh.
- Closing Neovim intentionally clears continuation memory.
- Each response is retained as a page for the lifetime of Neovim.

Float controls:

| Key | Action |
| --- | --- |
| `<leader>P` | Focus, unfocus, or restore the Float |
| `<M-h>` / `<M-l>` | Previous / next response page |
| `<M-u>` / `<M-d>` | Scroll up / down |
| `q` / `<Esc>` | Close while focused |

Float visibility has `before_open` and `after_close` lifecycle hooks. They run
once per hidden/visible transition, not for page changes. The local
no-neck-pain integration uses them to expand the center window while the Float
is visible and restore its previous width afterward.

## Generate

Generate is a one-shot, stateless process.

- Normal mode inserts completed output at the captured cursor.
- Visual mode replaces the captured selection.
- Output is buffered and applied only after the process completes.
- The inserted result becomes the active selection, making an immediate follow-up
  Generate request operate on that result.
- Undo rejects the change using normal Neovim behavior.
- Generate does not clear or join the current Read session.

There is no generated-alternative history and no streamed ghost-code acceptance
flow. Further revisions use the current buffer as context for another one-shot
request.

## Session handoff

Session handoff finds the active pane in the configured tmux window, validates
that it runs the configured executable, pastes the rendered request, and submits
it.

- It does not start a process from Neovim.
- It does not require a built-in runtime adapter.
- It does not change tmux or Neovim focus.

The default tmux window name is `agent` and is configurable with
`target_window_name`.

## Runtime support

Runtime adapters are currently built in. The executable and runtime are separate
so forks, wrappers, and local development builds can share a protocol. A future
standalone plugin may expose runtime registration for additional agents such as
OpenCode or Claude Code.

## Intentional limits

- Continuation discovery does not survive a Neovim restart.
- Generate has no conversational state or alternative history.
- Tmux handoff is send-only.
- Runtime registration is not public yet.
