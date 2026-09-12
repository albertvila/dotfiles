# Use a `home/` mirror as the single dotfile layout

We unify the repo around one layout: every managed dotfile lives in `home/`, mirroring its path under `$HOME` (e.g. `home/.config/opencode/opencode.json` → `~/.config/opencode/opencode.json`). `setup.sh` walks the tree and symlinks each file, replacing the flat `FILES_TO_SYMLINK` array.

The array had grown awkward mappings (`zsh/scripts` → `~/.scripts`) and would not scale to the AI-tool configs being added (`~/.claude/`, `~/.config/opencode/`, `~/.pi/`). A single mirror rule is self-documenting: browsing the repo equals browsing `$HOME`. Alternatives considered: a GNU stow/chezmoi dependency (extra moving part for ~30 `ln -sf` lines we already own) and a grown `FILES_TO_SYMLINK` array (hand-maintained per-file mapping, exactly the divergence we're removing). The mirror is a one-time mechanical file move, recorded in one commit.

Status: accepted