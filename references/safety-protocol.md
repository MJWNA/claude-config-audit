# Safety Protocol

This skill modifies user-scope config that affects every Claude Code session on the user's machine. Every destructive action follows this protocol — no exceptions, even when the user is in auto mode.

## The non-negotiables

### 1. Quarantine, don't delete

Every "deletion" is actually a `mv` into a timestamped session under `~/.claude/.audit-quarantine/<ISO-timestamp>/`. The quarantine has a 7-day TTL and a one-line restore. Use the helper:

```bash
SESSION=$(bash <skill-dir>/scripts/quarantine.sh init)
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" <path-to-quarantine>
```

Why this matters: a destructive `rm -rf` against the user's `~/.claude/` is psychologically heavy, and users who feel that weight just don't run audits. `mv` to a quarantine that auto-purges after a week is reversible enough that they actually clean up, which is the whole point.

### 2. Snapshot files before editing

For files that will be edited rather than moved (the plugin manifest, rule files, `CLAUDE.md`, settings files), copy them into the quarantine session BEFORE editing:

```bash
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/plugins/installed_plugins.json --copy
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/CLAUDE.md --copy
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/rules --copy
```

The `--copy` flag preserves the original at its real location while putting a backup in the quarantine. If an edit goes wrong, restore the file from the quarantine session.

### 3. Always show the exact command list before executing

Even after the user has approved the plan in the markdown report, show the exact commands:

```
About to run:

# Initialise quarantine session
SESSION=$(bash <skill-dir>/scripts/quarantine.sh init)

# Snapshot files we're about to edit
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/plugins/installed_plugins.json --copy

# Edit the manifest atomically
python3 -c "<the actual python>"

# Move cache directories into quarantine
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/plugins/cache/<marketplace>/<plugin-a>
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/plugins/cache/<marketplace>/<plugin-b>

# Move standalone skill directories into quarantine
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/skills/<skill-a>
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/skills/<skill-b>

# Write the quarantine manifest
bash <skill-dir>/scripts/quarantine.sh manifest "$SESSION"

Reply 'go' to execute.
```

Wait for confirmation. The cost of showing it is one extra round-trip; the cost of not showing it is destroyed work that the user didn't sign up for.

### 4. Verify paths exist before quarantining

`mv` and `rm` against a non-existent path can silently succeed in some shells, masking the fact that the target wasn't touched. Always:

```bash
# Check first
ls ~/.claude/skills/<name>          # confirm it exists

# Only then quarantine
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/skills/<name>
```

For batches:

```bash
# Confirm all exist first
for s in skill-a skill-b skill-c; do
  if [ -d ~/.claude/skills/$s ]; then
    echo "  ✓ $s"
  else
    echo "  ✗ MISSING: $s"
  fi
done
# Only proceed if all show ✓
```

### 5. Read files before editing them

The Edit tool requires you to have Read the file in the same conversation before editing — this isn't bureaucracy, it's how the tool prevents stale-anchor edits. Always:

```
Read /path/to/file
Edit /path/to/file ...
```

In sequence. Don't try to Edit based on memory of an earlier Read in a different turn.

### 6. Edit manifest BEFORE moving cache dirs

Order matters:

1. Edit `installed_plugins.json` to remove the entry
2. THEN `mv` the cache directory into quarantine

If you move the cache first, Claude Code may try to load the plugin on next start, find the cache missing, and produce confusing errors. Editing the manifest first cleanly de-registers the plugin; the cache move is just disk-space management.

### 7. Save decisions to history before declaring done

```bash
python3 <skill-dir>/scripts/audit-history.py save skills <markdown-path>
python3 <skill-dir>/scripts/audit-history.py save rules <markdown-path>
```

This persists the user's decisions (including the reasons for any agent overrides) so the next audit can surface only deltas. Skipping this means the user re-walks every item next time.

### 8. Restart-prompt at the end

Plugin changes don't take effect until Claude Code reads the manifest at session start. Always end with:

```
🔄 Restart Claude Code now (quit + relaunch) to load the trimmed config.

If anything's wrong, restore from quarantine:
  bash <skill-dir>/scripts/restore.sh <quarantine-session-path>
```

If the user is on a terminal multiplexer, mention they need to fully exit Claude Code, not just close a tab.

## Plugin uninstallation — the anatomy

When you "uninstall" a plugin via this skill, you're moving:

1. **Manifest entry** (edited in place, original snapshotted to quarantine) — `~/.claude/plugins/installed_plugins.json` → `plugins.<key>`. This is the source of truth Claude Code reads at session start.
2. **Cache directory** (moved into quarantine) — `~/.claude/plugins/cache/<marketplace>/<plugin-name>/<version>/`. Contains the actual plugin files (skills, agents, commands, hooks).
3. **Optionally**: orphaned MCP server registrations in user-scope settings. Most plugins ship their MCP servers via the plugin's own `plugin.json` — removing the manifest entry de-registers the MCP. But check `~/.claude/settings.json` and `~/.claude/settings.local.json` for `mcpServers` keys that might reference the plugin.

```bash
# Check for orphaned MCP server registrations
python3 -c "
import json, os, sys
home = os.path.expanduser('~')
for f in [f'{home}/.claude/settings.json', f'{home}/.claude/settings.local.json']:
    try:
        with open(f) as fp: d = json.load(fp)
        servers = d.get('mcpServers', {})
        if servers:
            print(f'{f}: {list(servers.keys())}')
    except FileNotFoundError:
        pass
"
```

If anything shows up, ask the user before touching it. Settings edits are not part of the default scope.

## Standalone skill removal — simpler

A standalone skill is just a directory at `~/.claude/skills/<name>/` containing a `SKILL.md`. Move the directory into quarantine and the skill is gone from active config:

```bash
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/skills/<name>
```

(After verifying the path exists, per rule 4.) No manifest edit needed.

## Rules half — different but parallel

For the rules half:

- **Adding a new rule** — `Write` to `~/.claude/rules/<name>.md`. Reversible: `rm ~/.claude/rules/<name>.md` (or `quarantine.sh add` if you want a soft delete). Non-destructive of any existing data.
- **Editing an existing rule** — Snapshot first (`quarantine.sh add ... --copy`), then `Read` then `Edit`. The original is preserved in the quarantine session.
- **Deleting a rule** — Same as standalone skill: `quarantine.sh add` to move it.
- **Editing CLAUDE.md** — Snapshot first, then Read, then Edit precisely. The CLAUDE.md rule index is the most-read part of the file; mistakes here mislead the user every session.

## What if the user wants to "undo everything"

Single command, regardless of which half they ran:

```bash
bash <skill-dir>/scripts/restore.sh <quarantine-session-path>
```

If they don't remember the session path:

```bash
bash <skill-dir>/scripts/quarantine.sh list
```

Lists every session with age in days and item count.

## What we explicitly don't protect against

- **`rm -rf /` typos by the user themselves** — the skill never operates outside `~/.claude/`, but if a user runs an arbitrary `rm -rf` based on something they read, that's not the skill's job to prevent.
- **Symlink shenanigans** — if the user has symlinked their `~/.claude/` to somewhere unusual, the skill operates on the symlink target. We trust the user knows their setup.
- **Concurrent Claude Code sessions** — if the user has two Claude Code sessions open and runs the audit in one, the other will see stale config until restart. Mention this if you spot it.
- **Quarantine purge while a session is in use** — if the user runs `quarantine.sh purge` immediately after the audit (rather than waiting the TTL), the safety net is gone. The script doesn't prevent this.

## When in doubt, refuse

If a deletion plan looks weird (user says "delete everything", or the markdown report has zero items in Keep, or the security-pass agent flagged something the user didn't mention reviewing), stop and ask. Auto mode does not override "destructive operations need confirmation".
