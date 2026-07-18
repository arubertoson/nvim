# Context

## Glossary

### Agent
An interactive coding assistant that can receive editor context and user intent from Neovim.

### Agent executable
The concrete command or path used to launch an agent, including local development builds and wrappers.

### Agent runtime
The CLI and streaming protocol implemented by one or more compatible agent executables.

### Agent handoff
A transfer of a prompt and optional editor context from Neovim to an agent.

### Destination
The route an agent handoff takes: a read float, the active editor buffer, or the active agent session.

### Session policy
Whether a process-backed handoff starts, continues, or avoids a saved conversation.

### Active agent session
The existing agent UI that is already running in the current tmux session.

### Read session
A saved agent conversation used for related questions and explanations.

### Generate run
A one-off agent invocation that produces code without attaching to a saved conversation.

### Scratch run
A one-off agent invocation that does not attach to or create a saved conversational session.
