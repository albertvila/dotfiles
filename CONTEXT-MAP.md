# Context Map

This repository holds two contexts: the dotfiles layer that provisions a machine,
and the orchestrate skill family that runs multi-agent work.

## Contexts

- [Dotfiles](./CONTEXT.md): the home mirror, setup, and per-user config that provision a machine
- [Orchestrate](./home/.agents/skills/orchestrate-core/CONTEXT.md): runs an approved manifest of items through dispatched lanes and records the run

## Relationships

- **Dotfiles → Orchestrate**: Dotfiles versions the orchestrate skills as managed config; the orchestrate context never decides how a machine is provisioned.
- **Orchestrate → Dotfiles**: an orchestrate run edits the repository it was pointed at, which is usually another project, and its retro proposes edits to its own skills.
