# Aru Neovim Configuration

Personal Neovim configuration organized around the editing behaviors it owns.

## Language

**Behavior**:
A cohesive editor-facing capability, such as file exploration, language completion, or scratch execution. A behavior owns its configuration, lifecycle, and mappings.
_Avoid_: feature, plugin config

**Integration**:
An explicit adaptation between two independently owned behaviors, such as coordinating the centered layout with Psst’s response float.
_Avoid_: glue, workaround
