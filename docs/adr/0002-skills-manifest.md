# Version skills by manifest, never by vendoring their content

We treat skills as **derived content**: installable on a machine by a package manager, reproducible from a lockfile, and never committed into the mirror. `skills-lock.json` (and `~/.agents/.skill-lock.json`) records each installed skill's source (git repo, path, hash); those **Skill manifests** are versioned here so a fresh machine reproduces the skill set via `skills update`.

The tempting alternative was vendoring installed skills into `home/.claude/skills/` wholesale. That drags third-party updates into this repo's diffs, breaks the mirror's 1:1 `$HOME` illusion (manager-written content like node_modules, sessions, and auth would appear as "dotfiles"), and forks the source of truth away from the upstream repos. Lockfile-only keeps the mirror a repo of hand-authored configuration plus reproducibility metadata.

One deliberate exception: `unani-metricas` is the sole **hand-authored** skill, authored for this user rather than installed from an upstream source, and is therefore managed content versioned in `dotfiles.private`.

Status: accepted