# Context

## Glossary

### Agent
An interactive coding assistant runtime that can receive editor context and user intent from Neovim.

### Agent handoff
A transfer of a prompt and optional editor context from Neovim to an agent.

### Destination
The route an agent handoff takes. Current destinations are the active agent session, a new saved agent session, or a scratch run.

### Active agent session
The existing agent UI that is already running in the current tmux session.

### Scratch run
A one-off agent invocation that does not attach to or create a saved conversational session.
