# Safety Guarantees

What can go wrong, what can't go wrong, and what to do if something does.

## What this skill modifies

User-scope only. The skill is hard-bounded to `~/.claude/`.

| Path | Operation | Reversible? |
|---|---|---|
| `~/.claude/plugins/installed_plugins.json` | Atomic Python edit, copy to quarantine first | Yes — restore from quarantine |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/` | `mv` to quarantine, not `rm -rf` | Yes — restore from quarantine, 7-day TTL |
| `~/.claude/skills/<skill-name>/` | `mv` to quarantine | Yes — restore from quarantine, 7-day TTL |
| `~/.claude/rules/*.md` | `Write` (new) or `Edit` (existing); existing files copied to quarantine first | Yes — restore from quarantine |
| `~/.claude/CLAUDE.md` | `Edit`; copied to quarantine first | Yes — restore from quarantine |
| `~/.claude/.audit-quarantine/` | Created and managed by the skill | N/A — the safety net itself |
| `~/.claude/.audit-history/` | Append-only JSON of past audit decisions | Yes — delete the file if you don't want the memory |

## What this skill does NOT modify

- **Project-scope `.claude/` directories** — the rules audit can READ project rules to identify cross-project promotion candidates, but never modifies them. Project-scope changes are the user's job, per project.
- **`~/.claude/settings.json` / `settings.local.json`** — read-only by default. The security-pass agent flags concerns; the user decides whether to act on them and edits manually.
- **Anything outside `~/.claude/`** — the scripts have a hard refuse-to-operate-outside guard.
- **Git state of any project** — no commits, no branches, no working-tree changes.
- **The Claude Code application itself** — no install/uninstall, no settings beyond the manifest.
- **MCP server data dirs** — if a plugin stored data at `~/.claude/plugins/data/<plugin>/`, that's left alone. The user can clean it up separately if they want.

## Quarantine instead of delete

This is the v2 safety model. Every "deletion" is actually a `mv` into a timestamped session under `~/.claude/.audit-quarantine/<ISO-timestamp>/`. A `MANIFEST.md` documents what's there and how to restore.

### Restore everything

```bash
bash <skill-dir>/scripts/restore.sh <session-dir>
```

Reverses every `mv` from that session. Refuses to overwrite anything that was re-created at the original path (gives you a manual resolution recipe instead).

### Restore a single item

The flattened naming in the quarantine (`a--b--c` for `~/.claude/a/b/c`) is reversible by hand:

```bash
mv ~/.claude/.audit-quarantine/<session>/<flattened-name> ~/.claude/<original-path>
```

### Auto-purge after TTL

```bash
bash <skill-dir>/scripts/quarantine.sh purge
```

Removes sessions older than 7 days. Idempotent — safe to run on a cron. The TTL is configurable via `CLAUDE_CONFIG_AUDIT_TTL_DAYS`.

## Safety rails enforced by the skill

### 1. Confirmation before any destructive action

Even after the user approves the plan in the markdown report, the skill shows the exact commands and waits for "go". Auto mode does not override this rail. The cost of one extra round-trip is small; the cost of an unwanted change is large.

### 2. Path verification before `mv` or `rm`

The skill always `ls`s a path before operating on it. If the path doesn't exist, the operation is skipped and the user is told. This catches typo-class bugs where the wrong path slips into the deletion plan.

### 3. Manifest edit before cache move

Always: edit `installed_plugins.json` first, then `mv` cache directories. If you swap the order, Claude Code may try to load a plugin on next start, find the cache moved, and produce confusing errors. Editing the manifest first cleanly de-registers the plugin; the cache move is just disk-space management.

### 4. Read before edit

The skill always `Read`s a file before `Edit`ing it. The Edit tool requires this — without a prior read, anchor-string matching can't safely identify the target lines.

### 5. Snapshot before edit

For rule files and CLAUDE.md, the skill copies the file into the quarantine session BEFORE editing. This way an "edit" is also reversible — even though the file is still in place, the original is preserved.

### 6. Single file at a time for edits

The skill doesn't batch-rewrite multiple files in one transaction. Each rule edit is a separate Read + Edit. This makes errors recoverable at the file level — a typo in one rule edit doesn't corrupt others.

### 7. Hard guard against operating outside ~/.claude/

The quarantine + restore scripts both refuse to operate on paths outside `~/.claude/`. A malformed caller passing `/etc/passwd` or similar will get an error, not damage.

## What can NOT be undone

- **A plugin's user-state stored at `~/.claude/plugins/data/<plugin>/`** — the skill leaves these alone, but if you decide to clean them up separately, they're gone.
- **Auto-memory entries inside deleted projects' memory dirs** — the skill doesn't touch these, but if you also clean up `~/.claude/projects/`, you'd lose the auto-memory.
- **Quarantine sessions older than the TTL** — once `quarantine.sh purge` runs, those items are gone. Restore within 7 days (or extend the TTL).

## Concurrent sessions

If the user has two Claude Code sessions open and runs the audit in one:

- The other session continues with the OLD config until it restarts.
- Mostly harmless, but if the other session is mid-task and tries to invoke a moved plugin, it'll fail.
- Recommendation: close other Claude Code sessions before running the audit.

## What if Claude Code itself breaks

If the audit goes wrong and Claude Code won't start:

1. **Restore from the quarantine session:**
   ```bash
   bash <skill-dir>/scripts/restore.sh <session-dir>
   ```

2. **Re-install missing plugins** if you've already let the quarantine purge:
   - Open Claude Code
   - Use `/plugin install <name>` for each one you want back

3. **Nuclear option** — if nothing else works, reset the entire user-scope config:
   ```bash
   mv ~/.claude{,.broken-$(date +%Y%m%d)}
   # then re-launch Claude Code, which recreates ~/.claude/ on first run
   ```

   Your `~/.claude.broken-*` is preserved for forensics.

## Reporting safety issues

If you discover a way for this skill to:

- Modify state outside `~/.claude/`
- Skip the confirmation gate before destructive operations
- Lose data that wasn't part of the deletion plan
- Corrupt the manifest in a way that breaks recovery
- Path-traverse via crafted plugin/skill names that escape the cache directory
- Execute code from agent output rather than displaying it

… use GitHub's private vulnerability reporting (see `SECURITY.md`). Safety bugs are highest priority.
