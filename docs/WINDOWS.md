# Running on Windows

Short version: use **WSL2**. Native Windows works for read-only inspection but the destructive paths need a POSIX shell, and the plugin layout depends on filesystem symlinks.

## Why WSL2

The skill ships scripts in `bash` and `python3`. It uses POSIX `mv`, `cp -R`, `find`, `mktemp`, and process substitution. None of these are available in `cmd.exe` or PowerShell without a shim layer. WSL2 gives you a real Linux user-space and the symlinks in this repo resolve correctly under ext4. It is the supported path.

The skill also uses filesystem symlinks for the plugin-canonical layout (`skills/claude-config-audit/SKILL.md → ../../SKILL.md`). On Windows, git only honours these symlinks when:

- The user is running with **Developer Mode enabled**, OR
- Running with elevated permissions, AND
- The clone was performed with `git config --global core.symlinks true` set first

Without those, git silently materialises the symlinks as 12-byte text files containing the link target as a string. The skill loader then sees a file at `skills/claude-config-audit/SKILL.md` that says `../../SKILL.md` — not your skill. The plugin-install path appears to work, but plain-language triggering is broken.

## Recommended setup

```powershell
# Install WSL2 (PowerShell, run as Administrator)
wsl --install

# Reboot when prompted, then open Ubuntu and continue inside WSL
```

Inside WSL:

```bash
# Install Claude Code per the official docs (https://code.claude.com)
# Then install the plugin as normal:
/plugin marketplace add MJWNA/claude-config-audit
/plugin install claude-config-audit@claude-config-audit
```

WSL2's filesystem honours symlinks identically to macOS and native Linux, so the dual-install layout works without any extra configuration.

## If you really must use native Windows

You can run the skill on native Windows under Git Bash (bundled with [Git for Windows](https://git-scm.com/download/win)), but you must enable symlink support in git BEFORE cloning:

```bash
# 1. Enable Windows Developer Mode (Settings → Privacy & Security → For developers)

# 2. Configure git
git config --global core.symlinks true

# 3. Clone — symlinks now resolve to their targets
git clone https://github.com/MJWNA/claude-config-audit.git ~/.claude/skills/claude-config-audit
```

To verify the symlinks resolved correctly after clone:

```bash
# These should all show file sizes > 1KB. If you see ~12 bytes,
# the symlinks were materialised as text files — re-clone with
# Developer Mode + core.symlinks=true.
ls -l ~/.claude/skills/claude-config-audit/SKILL.md
ls -l ~/.claude/skills/claude-config-audit/scripts
```

The CI pipeline runs a Windows job that checks-out with `git config core.symlinks true` and asserts `wc -c < skills/claude-config-audit/SKILL.md > 1000` — exactly the canary that catches the broken-symlink-as-text-file failure mode. If your local install passes the same check, you're good.

## What works without POSIX

These run on any Windows shell:

- **Plugin install via `/plugin install`** — Claude Code handles the install itself, no script execution required
- **Reading the skill description** — driven by SKILL.md content alone
- **Triggering via slash command** — `/audit-skills`, `/audit-rules` work
- **Browser HTML decision tools** — pure JS/CSS, no platform dependency

## What needs POSIX

These require WSL2 or Git Bash with the symlink config above:

- **`scripts/discover-config.sh`** — uses `find`, `stat`, BSD/GNU detection
- **`scripts/quarantine.sh`** — uses `mv`, `mktemp -d`, process substitution
- **`scripts/restore.sh`** — uses `find`, `mv`, process substitution
- **`scripts/verify-prerequisites.sh`** — uses `find`, `[`, `printf`
- **`scripts/audit-history.py`** — pure Python, but the shebang line `#!/usr/bin/env python3` requires a POSIX `env`

The Python scripts work directly on native Windows when you invoke them as `python scripts\audit-history.py ...` rather than relying on the shebang. The bash scripts genuinely need a POSIX shell.

## Reporting Windows-specific bugs

When you file a bug:

1. State which path you're on — WSL2, Git Bash, or native PowerShell
2. Confirm symlinks resolved: paste output of `ls -l ~/.claude/skills/claude-config-audit/SKILL.md`
3. Confirm `python3 --version` and `bash --version` work in your shell

Most "the skill doesn't work on Windows" reports turn out to be the symlink-materialised-as-text-file case, which the steps above catch before the audit ever runs.
