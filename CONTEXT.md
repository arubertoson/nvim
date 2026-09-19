# Neovim Agent Interaction

The Neovim agent integration sends editor context to an external agent while keeping short-lived read conversations navigable inside the editor.

## Language

**Agent Session**:
A conversation started and owned by the Neovim integration. It groups related Read responses and has an identity that can be resumed explicitly.
_Avoid_: Page history, request history

**Response**:
The visible output of one Read request within an Agent Session. Responses are retained for navigation without retaining the submitted prompt.
_Avoid_: Page, turn, message

**Selected Session**:
The Agent Session currently shown by response navigation and targeted by Continue when it belongs to the current working directory.
_Avoid_: Last session, current page

**Session Store**:
The disposable collection of external session files owned exclusively by the Neovim integration. Clearing it never affects sessions created outside the integration.
_Avoid_: Pi history, global sessions

**Inline Reference**:
Prompt syntax that names file content to attach, optionally narrowed to a line range or symbol. Its meaning is derived entirely from the current prompt text.
_Avoid_: Mention, attachment state

**Context Item**:
One resolved unit of source or diagnostic content attached to an agent request. A Context Item may come from editor invocation state, an explicit collector, or an Inline Reference.
_Avoid_: Prompt file, reference object

**Context Preview**:
The prompt-owned presentation of Context Items and unresolved Inline References that would affect submission. It is derived metadata, not a stored request.
_Avoid_: Payload state, attachment list
