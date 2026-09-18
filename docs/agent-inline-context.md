# Agent Inline Context

## Status

Proposed.

## Objective

Allow a prompt to name additional editor context inline, complete file paths and
symbols while the prompt is being written, show the context that would be sent,
and render the final request using Pi-compatible file attachments.

Inline context must remain text-driven: the current prompt text is the source of
truth. Editing, completing, invalidating, or deleting a reference must update the
attached context without maintaining a second mutable reference list.

## Scope

This specification covers:

- inline file, line-range, and symbol references;
- path and symbol completion in the agent prompt;
- reference parsing and derived reference states;
- live compact context preview and an exact payload preview;
- reference highlighting;
- context composition and deduplication;
- submission-time resolution; and
- Pi-compatible payload rendering.

The feature applies to Read, Generate, and tmux handoff requests created through
the prompt. Agent Session and Response history remain unchanged.

## Domain model

```lua
---@alias aru.agent.reference.State "editing"|"resolved"|"unresolved"

---@class aru.agent.reference.Span
---@field start_row integer 0-based
---@field start_col integer 0-based byte offset
---@field end_row integer 0-based
---@field end_col integer 0-based exclusive byte offset

---@class aru.agent.reference.Reference
---@field raw string
---@field path string|nil
---@field selector aru.agent.reference.Selector|nil
---@field span aru.agent.reference.Span
---@field state aru.agent.reference.State
---@field error string|nil
---@field context aru.agent.payload.ContextItem|nil

---@class aru.agent.reference.LineSelector
---@field kind "lines"
---@field start_line integer
---@field end_line integer

---@class aru.agent.reference.SymbolSelector
---@field kind "symbol"
---@field name string

---@alias aru.agent.reference.Selector
---| aru.agent.reference.LineSelector
---| aru.agent.reference.SymbolSelector
```

A Reference is derived from prompt text. It is not an independently owned
object that survives text changes. A Context Item is the resolved source content
that will be attached to a request.

### Invariants

- Prompt text is the only durable source of inline references.
- Every preview refresh reparses the prompt and derives a new reference set.
- Only resolved references contribute Context Items.
- An editing or unresolved reference never leaves its previous Context Item
  attached.
- Completion acceptance does not create hidden reference state.
- Manual typing and completion acceptance produce identical results.
- Submission resolves references again against current buffer contents.
- Explicit references are combined with, not substituted for, invocation and
  collector context.
- Context rendering is independent of the selected request destination.

## Reference syntax

The supported forms are:

```text
@path
@path:start-end
@path#symbol
@#symbol
```

Examples:

```text
@lua/aru/agent.lua
@lua/aru/agent.lua:120-180
@lua/aru/agent.lua#send
@#send
```

Paths are resolved relative to the working directory captured when the prompt
opens. `@#symbol` resolves against the invocation buffer captured when the
prompt opens.

References may be wrapped in Markdown backticks:

```text
Compare `@lua/aru/agent.lua#send` with `@lua/aru/agent/runtime.lua:20-45`.
```

Backticks are delimiters and are not part of the reference.

### Lexical boundaries

A reference starts at `@` when it appears at the start of text or after
whitespace, a backtick, or opening punctuation. This prevents ordinary email
addresses from becoming references.

A reference ends at whitespace, a closing backtick, or closing prose
punctuation such as `,`, `;`, `.`, `!`, `?`, `)`, `]`, or `}`. Path separators,
periods inside a path, underscores, hyphens, and symbol punctuation such as `.`
and `::` remain part of the reference.

Paths containing unescaped whitespace and filenames ending in closing prose
punctuation are outside the initial scope. Backticks disambiguate references in
prose but do not make whitespace part of a path.

## Derived reference states

The implementation must not maintain a mutable state machine alongside the
prompt. It computes reference states from the latest prompt text and cursor
position.

### Editing

A reference is `editing` when it is incomplete, does not currently resolve, and
the cursor remains inside its span.

Examples:

```text
@lua/aru/agen|
@lua/aru/agent.lua#|
@lua/aru/agent.lua#sen|
@lua/aru/agent.lua:120-|
```

An editing reference contributes no Context Item and is not presented as an
error.

### Resolved

A reference is `resolved` when it identifies exactly one file, valid range, or
symbol. Resolution does not require the cursor to leave the reference.

Examples:

```text
@lua/aru/agent.lua
@lua/aru/agent.lua#send
@lua/aru/agent.lua:120-180
```

A resolved reference contributes one Context Item.

### Unresolved

A reference is `unresolved` when it cannot resolve and the cursor is no longer
inside it, or when its syntax is complete but invalid.

Examples include a missing file, a missing or ambiguous symbol, a reversed line
range, and a range outside the target buffer.

An unresolved reference contributes no Context Item. The preview displays it
with a `?` marker and submission is refused with a concise notification naming
the first unresolved reference.

### Concrete transitions

Given this sequence:

```text
@lua/aru/agen
@lua/aru/agent.lua
@lua/aru/agent.lua#
@lua/aru/agent.lua#send
@lua/aru/agent.lua#sen
```

The derived states and context are:

| Text | State | Attached explicit context |
| --- | --- | --- |
| `@lua/aru/agen` while editing | editing | none |
| `@lua/aru/agent.lua` | resolved | whole file |
| `@lua/aru/agent.lua#` | editing | none |
| `@lua/aru/agent.lua#send` | resolved | symbol range |
| `@lua/aru/agent.lua#sen` while editing | editing | none |
| `@lua/aru/agent.lua#sen` after leaving it | unresolved | none |
| reference deleted | absent from parse result | none |

Adding `#` or `:` to a resolved whole-file reference immediately removes the
whole-file Context Item until the new selector resolves. Deleting a reference
removes its Context Item on the next refresh.

## Resolution

Resolution is the shared operation used by completion, preview, and submission.
There is no separate validation subsystem.

### Buffer choice

When a referenced path already has a loaded Neovim buffer, resolution reads that
buffer, including unsaved changes. Otherwise it loads the file into a hidden
buffer. This keeps context consistent with what the user currently sees in the
editor.

Missing external files are expected unresolved outcomes. Internal failures to
read a valid loaded buffer are errors and must surface visibly.

### Files

A path without a selector resolves to the complete buffer contents. Directories
do not resolve as Context Items.

### Line ranges

A range resolves when:

- both endpoints are positive integers;
- `start_line <= end_line`; and
- `end_line` does not exceed the current buffer line count.

The resulting Context Item contains exactly that inclusive range.

### Symbols

Symbols are indexed from Treesitter named nodes representing functions, methods,
classes, and declarations. The resolver obtains each candidate's name and outer
node range.

An exact unique name resolves to that node's complete outer range. No match is
unresolved. Multiple exact matches are ambiguous and unresolved; candidates must
remain distinguishable in completion by line range.

The initial implementation uses Treesitter only. LSP document symbols and
language-specific fallback scanners are outside scope.

Symbol indexes may be cached by buffer number and `changedtick`. A changed tick
invalidates the cache.

## Completion

Completion is prompt-specific and uses the same resolver data as preview.

### Path completion

Typing `@` opens project-relative path completion. Existing path completion
continues through nested directories.

Selecting a file inserts only its relative path after `@`. A selected directory
continues path completion and does not create context.

### Symbol completion

Typing `#` after a resolvable file path switches to a symbol provider:

```text
@lua/aru/agent.lua#
```

Candidates include their kind and range:

```text
send                    Function   126-174
prompt                  Function   180-188
PromptOpts              Class       46-49
resolve_session_policy  Function   115-122
```

Accepting a candidate inserts its symbol name. `@#` performs the same completion
against the invocation buffer.

The symbol provider returns no candidates until its file prefix resolves.

### Completion mappings

The prompt must preserve Blink navigation while its menu is visible:

- `<C-n>` selects the next item;
- `<C-p>` selects the previous item; and
- the existing smart-accept mapping accepts the selected item.

The prompt's tmux handoff mapping currently uses `<C-p>`. It must submit to tmux
only when the completion menu is not visible; while the menu is visible Blink
owns `<C-p>`.

No line-number completion is required after `:`.

## Live context preview

The prompt owns one debounced preview refresh. `TextChanged` and `TextChangedI`
schedule a refresh after 75–100 ms. A newer text change supersedes the pending
refresh.

Completion acceptance and moving the cursor out of a reference request an
immediate refresh. Submission bypasses the debounce and resolves synchronously.

The preview refresh must be side-effect-free from the user's perspective: it
must not notify for an absent optional diagnostic, move windows, change the
cursor, or submit a process.

### Compact footer

The footer displays resolved context in request order:

```text
ctx 4 · block agent.lua:181-188 · diagnostic · float.lua#send:402-438 · runtime.lua:35-72
```

`ctx N` counts Context Items that would be attached. Editing references use an
ellipsis marker and unresolved references use `?`:

```text
ctx 2 · block agent.lua:181-188 · …agent.lua#sen
ctx 1 · block agent.lua:181-188 · ?missing.lua#send
```

When the summary exceeds available width, retain the first entries and end with
`+N`. The action footer remains visible below or above the context summary.

### Inline highlights

Prompt-owned extmarks decorate complete reference spans:

- resolved: a subtle link or special highlight;
- editing: `Comment`;
- unresolved: `DiagnosticError`.

Extmarks are cleared and rebuilt from the latest parse result. They do not own
reference identity or context state.

### Exact payload preview

The prompt provides `<C-x>` to inspect the exact request that would be sent. It
opens a read-only temporary window containing the rendered payload, including
context blocks and the prompt text.

If references are unresolved, the preview still opens but begins with a clear
non-payload warning section naming them. The warning section is UI-only and is
never sent to the agent.

Closing the payload preview returns focus to the existing prompt without changing
its text or derived context.

## Context composition

A request combines context in this order:

1. invocation context, such as visual selection, enclosing block, or surrounding
   lines;
2. explicitly requested collectors, such as a diagnostic; and
3. resolved inline references in textual order.

Context Items with the same normalized path, start line, and end line are
included once. Overlapping but non-identical ranges are retained because they
may represent distinct user intent. A whole-file item does not silently remove
an explicitly named symbol or range.

Reference text remains in the user prompt. Attachments provide source content;
the references preserve the user's explanation of how that content should be
used.

## Payload rendering

Pi's native `@file` processing renders text files as:

```xml
<file name="/absolute/path">
contents
</file>
```

Source Context Items must follow that convention.

### Whole file

```xml
<file name="/absolute/path/to/agent.lua">
...
</file>
```

### Line range

```xml
<file name="/absolute/path/to/agent.lua" lines="120-180">
...
</file>
```

### Symbol

```xml
<file name="/absolute/path/to/agent.lua" symbol="send" lines="126-174">
...
</file>
```

The optional `lines` and `symbol` attributes are a conservative extension of
Pi's file format. Consumers may treat every block as ordinary named file content
without understanding those attributes.

Attribute values must be escaped. Source context blocks precede the original
prompt, matching Pi's native initial-message ordering:

```xml
<file name="/project/lua/aru/agent.lua" symbol="send" lines="126-174">
...
</file>

Compare @lua/aru/agent.lua#send with the current implementation.
```

Non-source context, such as diagnostics, retains a distinct descriptive tag.
The renderer must not depend on a model interpreting XML as a strict schema.

## Submission

Submitting with `<CR>`, `<C-CR>`, `<C-g>`, or tmux handoff performs an
authoritative synchronous context build:

1. Parse the current prompt.
2. Resolve every reference against current buffer contents.
3. Refuse submission if any reference is unresolved.
4. Resolve invocation and requested collector context.
5. Combine and deduplicate Context Items.
6. Render source items as Pi-compatible file blocks before the prompt.
7. Send the result through the selected destination's existing path.

An editing reference under the cursor is unresolved for submission. The
notification names the reference and does not mutate or close the prompt.

## Ownership and lifecycle

- The prompt session owns its debounce timer, reference extmark namespace, and
  payload-preview window.
- Closing the prompt stops and closes its timer, clears its extmarks, and closes
  its payload preview.
- Hidden buffers loaded solely for reference resolution remain subject to the
  existing buffer-cache policy.
- Reference and symbol caches contain derived data only and may be discarded at
  any time.
- No reference or preview state survives closing the prompt.

## Implementation boundaries

### Reference parser

`lua/aru/agent/reference.lua` owns syntax recognition, lexical spans, selector
parsing, and derived editing versus unresolved classification.

### Context resolver

`lua/aru/agent/context.lua` owns path normalization, buffer acquisition, file and
range extraction, Treesitter symbol indexing, resolution outcomes, context
composition, and exact-range deduplication.

### Symbol completion

`lua/aru/cmp/symbol.lua` adapts resolved symbol candidates to Blink completion
items. It must use the context resolver's symbol index rather than implementing a
second symbol scanner.

### Prompt

`lua/aru/agent/prompt.lua` owns debounce lifecycle, cursor-aware refresh,
reference extmarks, compact footer rendering, exact-preview presentation, and
submission refusal without closing the prompt.

### Payload

`lua/aru/agent/payload.lua` owns escaping and rendering typed Context Items. It
must render source context before prompt text and match Pi's whole-file format.

## Acceptance criteria

- Typing `@` opens project-relative path completion.
- A completed file reference appears in the context footer without leaving the
  reference.
- Adding `#` or `:` removes the former whole-file context until the selector
  resolves.
- Symbol completion after `#` lists Treesitter symbols from the referenced file.
- `@#symbol` resolves against the invocation buffer.
- File, symbol, and range references read unsaved loaded-buffer contents.
- Editing a resolved reference immediately removes stale context.
- Deleting a reference removes its context and highlight.
- An incomplete reference under the cursor is shown as editing, not as an error.
- Leaving an incomplete reference makes it unresolved.
- An unresolved reference prevents submission without closing the prompt.
- The compact footer accurately describes all context that would be attached.
- `<C-x>` shows the exact rendered payload and returns to the prompt when closed.
- Explicit references combine with invocation and diagnostic context.
- Exact duplicate ranges are rendered once.
- Whole files use Pi's native `<file name="...">` representation.
- Range and symbol source context use `<file>` with metadata attributes.
- Context blocks precede the unchanged user prompt.
- Read, Generate, and tmux handoff receive the same composed context.
- Closing the prompt releases all prompt-owned resources.
- The complete test suite passes via `just check`.

## Required tests

- lexical parsing for all four reference forms;
- reference boundaries in prose and Markdown backticks;
- cursor-aware editing versus unresolved classification;
- transition from whole file to incomplete and resolved symbol selectors;
- deletion removing derived context;
- relative path and current-file symbol resolution;
- valid, reversed, incomplete, and out-of-bounds ranges;
- exact, missing, and ambiguous symbols;
- symbol-cache invalidation by `changedtick`;
- unsaved loaded-buffer content winning over disk content;
- path and symbol completion candidates;
- `<C-p>` completion navigation versus tmux handoff;
- debounced refresh supersession and cleanup;
- compact preview formatting and truncation;
- reference extmark replacement;
- exact payload preview contents and lifecycle;
- context ordering and exact-range deduplication;
- Pi-compatible whole-file rendering;
- range and symbol metadata rendering with escaped attributes;
- submission refusal preserving prompt state;
- authoritative re-resolution after a referenced buffer changes; and
- identical context composition for Read, Generate, and tmux destinations.

## Out of scope

- Directory attachments.
- Paths containing whitespace.
- LSP document-symbol fallback.
- Cross-file symbol search without an explicit path.
- Symbol references that intentionally select multiple overloads.
- Automatic token budgeting, whole-file size limits, or truncation.
- Persisting prompt text, references, or preview state.
- Restoring inline references across Neovim restarts.
- Images or other binary attachments.
- Changing Agent Session or Response navigation.
