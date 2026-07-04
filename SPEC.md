# Pi–Neovim Integration Spec

## Overview

A tight integration between Neovim and Pi that covers three distinct interaction
modes. Each mode has a clear user intent, a defined interaction surface, and a
defined output target. Neovim does not try to replicate Pi's chat UI — it hands
off when conversation is the right tool.

---

## Interaction Modes

### 1. Generate (code response)

**Intent:** Produce code that lands directly in the buffer.

**Trigger:** User makes a selection (or surrounding context is grabbed
automatically), opens the prompt, types, submits with `<C-g>`.

**Flow:**
1. Context is collected — visual selection if active, otherwise surrounding
   code around cursor.
2. Prompt float opens (see Prompt UI). User types. `<C-g>` submits in generate
   mode.
3. Pi is invoked as a background process (`pi --mode json`). No Pi window
   interaction.
4. While streaming: a non-intrusive progress indicator is shown (statusline or
   corner spinner).
5. On first content token: response appears as ghost text at the selection site
   or cursor position. Streams in as tokens arrive.
6. When done: ghost text is finalised. `<Tab>` or `<CR>` accepts and inserts
   into buffer as plain text. `<Esc>` rejects and clears ghost text.
7. After accept the text is regular buffer content — user edits freely.

**Constraints:**
- No focus change at any point.
- No split or float opened for the response.
- Ghost text is visually distinct (dimmed highlight group).
- If no selection and no meaningful surrounding context exists, fall back to
  Read mode.

---

### 2. Read (question / reference response)

**Intent:** Get an answer to read, then get back to work.

**Trigger:** User opens the prompt, types, submits with `<CR>` (default).

**Flow:**
1. Context is collected — same rules as Generate.
2. Prompt float opens. User types. `<CR>` submits in read mode.
3. Pi is invoked as a background process (`pi --mode json`). No Pi window
   interaction.
4. While streaming: response streams into a floating window anchored to the
   upper-right corner of the screen.
5. Float has no focus. Cursor stays in the buffer.
6. `<Esc>` or `q` (while float is visible) closes it.
7. Float is scrollable without entering it via a dedicated scroll key
   (TBD during implementation).

**Float properties:**
- Anchored: upper-right corner, fixed position, does not follow cursor.
- Max height: 40% of screen height. Scrolls internally beyond that.
- Max width: fixed column count (TBD, ~60 cols).
- No border title beyond a minimal `pi` label.
- Streams content line by line as tokens arrive. No reflow or repositioning
  mid-stream.
- Auto-dismissed on `<Esc>` / `q`. Not auto-dismissed on cursor move.

---

### 3. Session (back-and-forth)

**Intent:** Start or continue a conversation that requires multiple turns.

**Trigger:** User opens the prompt, types, submits with `<C-p>`.

**Flow:**
1. Context is collected.
2. Prompt float opens. User types. `<C-p>` submits in session mode.
3. Payload is handed off to Pi (existing open Pi pane, existing saved session,
   or new session — see Destination Resolution below).
4. Neovim switches focus to the Pi pane. Neovim's job is done.
5. All further interaction happens inside Pi.

**Constraints:**
- Neovim does not render any Pi output for this mode.
- This is the only mode that changes focus.

---

## Prompt UI

A single floating input window. Appears on trigger keymap. Dismissed on submit
or `<Esc>`.

**Layout:**
```
╭─ pi ───────────────────────────────────────────╮
│ <user types here>                              │
│                                                │
│  [CR] read  [^G] generate  [^P] session        │
╰────────────────────────────────────────────────╯
```

**Properties:**
- Single-line input (multiline TBD, out of scope for v1).
- Footer shows the three submit actions at all times.
- `[^O]` indicator dims or shows a warning if no active Pi pane is detected
  (session mode unavailable).
- Appears near cursor, does not steal surrounding layout.
- `<Esc>` cancels with no side effects.

---

## Context Collection

Automatic, no user decision required.

**Priority order:**
1. Active visual selection — use selection text, file path, filetype,
   line range.
2. No selection — grab surrounding code around cursor (N lines above and below,
   TBD). Include file path and filetype.
3. No buffer / special buffer — no context attached. Prompt still works.

Context is snapshotted at submit time from the buffer (not disk). If buffer
content differs from disk, this is noted internally but does not block the
send (v1).

---

## Destination Resolution (Session mode)

When the user submits in session mode:

1. Look for an active Pi pane in the current tmux session (existing logic in
   `agent.lua`).
2. If found and idle: send payload to that pane.
3. If found and busy: TBD — out of scope for v1, treat as idle.
4. If not found: open a new Pi session with the payload.

New vs. existing saved session selection is out of scope for v1. Default
behaviour is to continue the current open session.

---

## Out of Scope (v1)

- Promoting from Read mode to Session mid-stream.
- Conflict detection (buffer vs. disk divergence warnings).
- Agent-busy detection.
- Multi-line prompt input.
- Scroll-without-focus implementation detail (keybinding TBD).
- Small screen fallback for the Read float (tmp scratch buffer).
- Selecting among multiple existing saved sessions.
- File write reconciliation (buffer reload after agent edits files).
