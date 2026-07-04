# Agent Interaction Model

## Goal

Build an in-editor learning companion for Neovim.

The agent should stay close to the code, answer questions from the current editor context, and help with understanding before changing anything. Neovim should gather local editor facts; the agent should explain, summarize, or generate based on the supplied context.

Core principle:

```text
I ask from where I am.
Neovim gathers local context.
Optional search/docs results are attached.
The agent answers using that context.
```

## Current state

The existing agent integration already has a useful base.

### Entry point

```text
<leader>p
```

Opens the Pi/agent prompt.

Behavior:

- normal mode: collects surrounding code
- visual mode: collects the selected code
- opens a floating prompt

### Prompt controls

Inside the prompt:

```text
<CR>   read     -- stream answer into a floating read window
<C-g>  generate -- stream generated code at cursor / selection site
<C-p>  session  -- hand off to the Pi session pane
<Esc>  close
<C-j>  newline
```

### Read float controls

```text
<leader>P -> focus/unfocus read float
<M-d>     -> scroll read float down
<M-u>     -> scroll read float up
```

### Supported destinations

```text
read      -> answer in floating read window
current   -> paste into current tmux agent pane
session   -> send payload through tmux session command
generate  -> generate code at cursor/selection
scratch   -> detached runtime process
```

### Context collected today

Current context collection is intentionally simple:

- visual selection if active
- otherwise surrounding lines around the cursor
- default surrounding range: 50 lines
- includes path, filetype, line range, and text

This gives us the pipeline:

```text
editor context -> prompt -> rendered payload -> agent destination
```

## Current weakness

The interaction is too generic.

Everything starts from:

```text
<leader>p -> type arbitrary prompt -> choose destination
```

There are no task-specific learning interactions yet:

- no “why diagnostic?”
- no “docs for symbol/topic”
- no “examples/usages”
- no “scout this topic”
- no search-enriched ask mode

The base is good, but it is not yet oriented around learning and local understanding.

## Desired model

Keep the generic prompt, but add fast task-specific interactions.

Most interactions should default to `read`, because the goal is understanding without leaving the code or mutating files.

Generation should remain explicit.

```text
read/scout/docs/examples -> explain
session                  -> larger discussion / handoff
generate                 -> code changes, only when requested
```

## Interaction categories

### 1. Ask about current context

Primary general-purpose interaction.

```text
<leader>p
```

Meaning:

> Ask a question about the current selection or surrounding code.

Default destination:

```text
read
```

Example prompts:

```text
What does this do?
Why is this structured this way?
What is the idiomatic way to write this?
Explain the control flow.
```

### 2. Why diagnostic?

Dedicated interaction for errors and warnings.

Proposed mapping:

```text
<leader>pw
```

Meaning:

> Explain the diagnostic under the cursor and suggest the smallest fix.

Collected context should include:

- diagnostic under cursor
- surrounding code
- file path/filetype
- later: LSP hover/current symbol context

Default destination:

```text
read
```

Generated prompt can be automatic:

```text
Explain this diagnostic and suggest the smallest fix.
```

### 3. Scout topic

Dedicated interaction for search/research.

Proposed mapping:

```text
<leader>ps
```

Meaning:

> Search code/docs/examples for this topic and summarize what I should look at.

Input:

- user-entered topic/question
- current file/symbol as weak context

Expected answer shape:

```text
Short answer
Relevant files
Relevant docs
Suggested next file to open
```

Default destination:

```text
read
```

Scout should not edit code.

### 4. Docs/knowledge for symbol or topic

Dedicated interaction for documentation lookup.

Proposed mapping:

```text
<leader>pk
```

Meaning:

> Find docs, guides, or reference material for the symbol under cursor or a typed topic.

Examples:

```text
vim.api.nvim_open_win
treesitter query predicates
Lua metatables
```

Default destination:

```text
read
```

### 5. Examples/usages

Dedicated interaction for examples from code, tests, docs, or guides.

Proposed mapping:

```text
<leader>pe
```

Meaning:

> Show examples/usages related to the current symbol or typed topic.

Useful sources:

- references/usages from LSP
- tests
- examples directories
- docs/guides
- later: semantic example search

Default destination:

```text
read
```

### 6. Generate/change code

Keep current prompt behavior:

```text
<C-g> inside prompt
```

Generation must stay explicit.

Rule:

```text
No learning interaction should modify code by default.
```

## Proposed keymap namespace

Keep Pi/agent interactions under `<leader>p`.

```text
<leader>p   generic prompt: ask about current context
<leader>P   focus/unfocus read float

<leader>pw  why diagnostic / why warning
<leader>ps  scout topic
<leader>pk  docs/knowledge for symbol or topic
<leader>pe  examples/usages
```

Prompt-local mappings remain:

```text
<CR>   read
<C-g>  generate
<C-p>  session
<Esc>  close
<C-j>  newline
```

## Destination rules

Use `read` when:

- answering local questions
- explaining code
- explaining diagnostics
- showing docs/examples
- scouting a topic

Use `session` when:

- the topic is larger than the current local context
- the user wants an ongoing threaded discussion
- the agent may need tools
- the work is project-level rather than local

Use `generate` when:

- the user explicitly asks to write or change code
- the user presses `<C-g>` in the prompt

## Use-cases and required information

This section defines what each interaction must deliver and what information Neovim/search needs to provide.

### 1. Ask about current code

Intent:

```text
Help me understand what I am looking at.
```

Required information:

- selected code, or surrounding code when there is no selection
- file path
- filetype/language
- line range
- current cursor position
- current symbol/function when available

Useful later:

- LSP hover/type information
- imports/module context
- nearby tests/usages
- related documentation

Expected answer:

- short explanation of what the code does
- important control flow or data flow
- relevant language/library concepts
- suspicious or non-idiomatic parts, if any

Minimum viable state:

```text
Already mostly covered by the current context collector.
```

### 2. Explain diagnostic

Intent:

```text
Explain why this error/warning is here and suggest the smallest fix.
```

Required information:

- diagnostic under cursor
- diagnostic message
- severity
- source
- diagnostic code when available
- exact diagnostic range
- surrounding code
- file path/filetype

Useful later:

- current symbol/function
- LSP hover/type information at the diagnostic range
- related diagnostics in the same file
- available code actions

Expected answer:

- what the diagnostic means
- why it applies to this code
- smallest likely fix
- whether the fix is mechanical or needs design judgment

Minimum viable state:

```text
diagnostic under cursor + surrounding code
```

### 3. Docs/knowledge for symbol or topic

Intent:

```text
Explain this API, symbol, or concept using relevant documentation.
```

Required information:

- symbol under cursor or typed topic
- filetype/language
- current file path
- current imports/module context when available
- documentation search results
- title/source/path/url for each result
- excerpt text for each result

Useful later:

- package/library context
- version metadata
- LSP hover/signature help
- related examples

Expected answer:

- short explanation
- relevant docs sections
- how the docs relate to the current code
- small example when useful

Minimum viable state:

```text
symbol/topic + documentation search output
```

### 4. Examples/usages

Intent:

```text
Show how this symbol, API, or concept is used elsewhere.
```

Required information:

- symbol under cursor or typed topic
- current file path/filetype
- LSP references when resolvable
- grep/search results when LSP is not enough
- snippets with file path and line ranges

Useful later:

- tests ranked above arbitrary source hits
- examples directories ranked above arbitrary source hits
- documentation examples
- semantic example search

Expected answer:

- best examples first
- why each example is relevant
- pattern worth copying
- caveats or differences from the current code

Minimum viable state:

```text
LSP references + surrounding snippets
```

### 5. Scout topic

Intent:

```text
Research this topic and tell me where to look.
```

Required information:

- typed topic/question
- current file/symbol as weak context
- code search results
- docs/guides search results
- examples/tests search results
- path/url/line metadata

Useful later:

- semantic search scores
- chunk kind: code, docs, guide, example, test
- package/library/version metadata
- ranking tuned for learning

Expected answer:

- short summary
- relevant files
- relevant docs/guides
- suggested reading order
- next file to open

Minimum viable state:

```text
user topic + external search results
```

### 6. Review current code or change

Intent:

```text
Review this code/change and point out issues before I commit to it.
```

This is a learning interaction, not an automatic editing interaction. It should explain problems and tradeoffs before suggesting changes.

Required information:

- selected code, current function, or current buffer region
- file path/filetype
- diagnostics in the selected/current range
- current symbol/function when available
- user-stated review focus when provided

Useful later:

- git diff or staged diff
- nearby tests
- usages/references of changed symbols
- project conventions from similar code
- relevant docs/examples for APIs used by the change

Expected answer:

- most important issues first
- correctness risks
- unclear or surprising code
- maintainability/design concerns
- missing tests or edge cases
- concrete improvement suggestions
- separate must-fix issues from optional improvements

Minimum viable state:

```text
selection/surrounding code + diagnostics
```

### 7. Compare code to docs/examples

Intent:

```text
Check whether this implementation matches the documented or idiomatic usage.
```

Required information:

- selected/current code
- docs for relevant API/concept
- examples/usages
- file path/filetype

Useful later:

- diagnostics
- tests around this code
- project-local conventions
- version-specific documentation

Expected answer:

- where the code matches the docs/examples
- where it differs
- whether the difference is intentional, risky, or likely wrong
- smallest improvement when needed

Minimum viable state:

```text
current code + relevant docs snippet
```

### 8. Generate/change code

Intent:

```text
Write or change code after the user explicitly asks for generation.
```

Required information:

- selected/surrounding code
- explicit user instruction
- file path/filetype
- line range or insertion point

Useful later:

- diagnostics
- docs/examples
- tests
- project conventions

Expected result:

- focused code change
- no hidden large refactors
- no mutation unless generation was explicitly requested

Minimum viable state:

```text
current generate behavior + better context
```

## Information categories

Reusable information types across use-cases:

### Editor context

- path
- filetype
- line range
- selected/surrounding code
- cursor position
- current symbol

### LSP context

- diagnostics
- hover
- signature help
- definition location
- references/usages
- code actions, later

### Project context

- cwd/git root
- package/dependency information
- nearby tests
- examples directories
- docs directories
- current git diff, for review flows

### Search context

- code chunks
- docs chunks
- guide chunks
- examples/tests chunks
- score/rank
- source metadata

## Suggested implementation order

```text
1. Explain diagnostic
2. Ask about current code + LSP hover/current symbol
3. Review current code/change
4. Examples/usages
5. Docs for symbol/topic
6. Scout topic
7. Compare code to docs/examples
8. Generate/change code with enriched context
```

## Summary

Current model:

```text
one generic prompt + simple code context + several destinations
```

Target model:

```text
generic prompt
+ fast task-specific prompts
+ Neovim-collected context
+ optional search/docs enrichment
+ read-first answers
+ explicit generation only
```

The result should feel like a local tutor/copilot: close to the code, quick to ask, evidence-based, and non-mutating unless generation is explicitly requested.
