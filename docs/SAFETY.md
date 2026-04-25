# Safety Guarantees

What can go wrong, what can't go wrong, and what to do if something does.

## What this skill modifies

User-scope only. Specifically:

| Path | Modified by |
|---|---|
| `~/.claude/plugins/installed_plugins.json` | Manifest edit (always backed up first) |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/` | `rm -rf` after manifest update |
| `~/.claude/skills/<skill-name>/` | `rm -rf` for deleted standalone skills |
| `~/.claude/rules/*.md` | `Write` (new files) and `Edit` (existing files) |
| `~/.claude/CLAUDE.md` | `Edit` (rule index updates) |

## What this skill does NOT modify

- **Project-scope `.claude/`** — no project rules, no project CLAUDE.md, no project skills
- **`~/.claude/settings.json` or `settings.local.json`** — except where MCP server cleanup is needed (and only after confirmation)
- **Anything outside `~/.claude/`** — the skill never operates beyond the user-scope Claude Code config
- **Git state of any project** — no commits, no branches, no working-tree changes
- **The Claude Code application itself** — no install/uninstall of CC, no settings beyond the manifest

## Backups

Every destructive action is preceded by a backup:

```bash
cp ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/installed_plugins.json.bak
```

The backup is kept indefinitely. Remove it manually when you're confident the audit is working:

```bash
rm ~/.claude/plugins/installed_plugins.json.bak
```

## What can be undone

| Change | How to undo |
|---|---|
| Manifest edit | `mv ~/.claude/plugins/installed_plugins.json{.bak,}` |
| Plugin cache deletion | Re-install the plugin via `/plugin install` (cache rebuilds) |
| Standalone skill deletion | Restore from version control or re-create the skill |
| New rule file created | `rm ~/.claude/rules/<name>.md` |
| Existing rule edited | Use git or filesystem snapshots; the skill doesn't snapshot rule files |
| CLAUDE.md edited | Same — use git or your own backup; the skill doesn't snapshot CLAUDE.md |

If you want full recoverability for rule edits and CLAUDE.md changes, version-control your `~/.claude/` directory before running the audit:

```bash
cd ~/.claude && git init && git add -A && git commit -m "before claude-config-audit"
```

This is optional but recommended for first-time audits.

## What can NOT be undone

- A plugin's user-state (any data the plugin stored at `~/.claude/plugins/data/<plugin>/`) — the skill leaves these alone, but if you decide to clean up data dirs separately, they're gone
- Auto-memory entries inside deleted projects' memory dirs — the skill doesn't touch these, but if you also clean up `~/.claude/projects/`, you'd lose the auto-memory

## Safety rails enforced by the skill

### 1. Confirmation before any destructive action

Even after the user approves the plan in the markdown report, the skill shows the exact commands and waits for "go." Auto mode does not override this rail.

### 2. Path verification before `rm -rf`

The skill always `ls`s a path before `rm -rf`-ing it. If `ls` shows nothing, the deletion is skipped and the user is told.

This caught a real near-miss during the original audit: the author confidently `rm -rf`'d `~/.claude/plugins/installed/` (deprecated path) when standalone skills lived at `~/.claude/skills/`. Nothing was damaged because nothing was at the wrong path, but it would have skipped the actual deletions.

### 3. Manifest edit before cache deletion

Always: edit `installed_plugins.json` first, then `rm -rf` cache. If you swap the order, Claude Code may try to load a plugin on next start, find the cache missing, and produce confusing errors.

### 4. Read before edit

The skill always `Read`s a file before `Edit`ing it. The Edit tool requires this — without a prior read, edits can't safely match anchor strings.

### 5. Single file at a time

The skill doesn't batch-rewrite multiple files in one transaction. Each rule edit is a separate Read + Edit. This makes errors recoverable at the file level — a typo in one rule edit doesn't corrupt others.

## What if Claude Code itself breaks

If the audit goes wrong and Claude Code won't start:

1. **Manifest restore:**
   ```bash
   mv ~/.claude/plugins/installed_plugins.json.bak ~/.claude/plugins/installed_plugins.json
   ```

2. **Re-install missing plugins:** open Claude Code, use `/plugin install <name>` for each one you want back.

3. **Rule file revert** (if version-controlled):
   ```bash
   cd ~/.claude && git checkout HEAD -- rules/ CLAUDE.md
   ```

4. **Nuclear option** — if nothing else works, reset the entire user-scope config:
   ```bash
   mv ~/.claude{,.broken-$(date +%Y%m%d)}
   # then re-launch Claude Code, which will recreate ~/.claude/ on first run
   ```

   Your `~/.claude.broken-*` is preserved if you need to extract anything later.

## Concurrent sessions

If the user has two Claude Code sessions open and runs the audit in one:

- The other session continues with the OLD config until it restarts
- This is mostly harmless — but if the other session is mid-task and tries to invoke a deleted plugin, it'll fail
- Recommendation: close other Claude Code sessions before running the audit

## What the skill won't touch even if asked

- Anything outside `~/.claude/`
- Project rule directories (`<project>/.claude/rules/`)
- Plugin source at random GitHub locations
- The `claude` CLI binary
- macOS Keychain entries (some plugins store secrets there — left alone)

If you want to clean up project-scope rules or anything outside `~/.claude/`, use a different tool. This skill is intentionally scoped.

## Reporting safety issues

If you discover a way for this skill to:

- Modify state outside `~/.claude/`
- Skip the confirmation gate
- Lose data that wasn't part of the deletion plan
- Corrupt the manifest in a way that breaks recovery

… file an issue at the GitHub repo with reproduction steps. Safety bugs are highest priority.
