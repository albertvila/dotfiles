# Dotfiles

Albert Vila's personal macOS configuration, kept under version control. Manages shell, git, editors, and AI-agent tooling across machines.

## Language

**Dotfile**:
A configuration file stored in this repo and symlinked into `$HOME`.
_Avoid_: Config, setup file

**Home mirror**:
The layout where `home/` in this repo mirrors `$HOME` 1:1 — a file at `home/.config/opencode/opencode.json` symlinks to `~/.config/opencode/opencode.json`.
_Avoid_: Stow layer, link manifest

**Managed config**:
Hand-authored configuration versioned in this repo and installed by `setup.sh`.
_Avoid_: Dotfile, installed config

**Derived content**:
Files installed on a machine by a package manager or marketplace (skills, plugins, language runtimes), never committed here. Reinstall on a fresh machine via the `skills` CLI or a declared installer; never version.
_Avoid_: Installed skill, node_modules, managed content

**Skill manifest**:
The lockfile the `skills` CLI writes (`skills-lock.json`, `~/.agents/.skill-lock.json`) recording each installed skill's source (git repo, path, hash). Versioned here so a fresh machine reproduces the skill set via `skills update`.
_Avoid_: Skill lock, installed-skills list

**Reproducible install**:
The property that a fresh machine reaches the baseline by running `setup.sh` plus the declared installer scripts for derived content.
_Avoid_: Bootstrapping, provisioning

**Per-user config**:
Custom packages/config layered on top of the defaults via `config_<user>.sh`, keeping identity and credentials in `dotfiles.private`.
_Avoid_: User profile, personal config

**Login shell**:
The interactive shell a terminal opens (prompt, completions, keybindings, env). The fish migration covers this and nothing else.
_Avoid_: Shell, terminal setup

**Script interpreter**:
The program that runs an executable script, fixed by its shebang line. Changing the login shell never changes it.
_Avoid_: Shell script runtime