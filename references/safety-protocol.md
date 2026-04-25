# Safety Protocol

This skill modifies user-scope config that affects every Claude Code session on the user's machine. Every destructive action follows this protocol — no exceptions, even when the user is in auto mode.

## The non-negotiables

### 1. Always backup before modifying `installed_plugins.json`

```bash
cp ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/installed_plugins.json.bak
```

The `.bak` file lives forever (or until the user deletes it). One-line recovery if anything goes wrong:

```bash
mv ~/.claude/plugins/installed_plugins.json.bak ~/.claude/plugins/installed_plugins.json
```

### 2. Always show the deletion command list before executing

Even after the user has approved the plan in the markdown report, show the exact commands:

```
About to run:

# Backup
cp ~/.claude/plugins/installed_plugins.json{,.bak}

# Plugin manifest edit (Python — atomic)
python3 -c "<paste actual python>"

# Cache directory removal
rm -rf ~/.claude/plugins/cache/<marketplace>/{plugin-a,plugin-b}

# Standalone skill removal
rm -rf ~/.claude/skills/{skill-a,skill-b}

Reply 'go' to execute.
```

Wait for confirmation. The cost of showing it is one extra round-trip; the cost of not showing it is destroyed work.

### 3. Verify paths exist before `rm -rf`

`rm -rf` against a non-existent path silently succeeds. This caused a real near-miss during the original audit — the author of this skill confidently `rm -rf`'d `~/.claude/plugins/installed/` (deprecated path) when the user's standalone skills lived at `~/.claude/skills/`. Nothing was damaged because nothing was there, but it would have skipped the actual deletions.

Always:

```bash
# Check first
ls ~/.claude/skills/<name>          # confirm it exists

# Then remove
rm -rf ~/.claude/skills/<name>
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

### 4. Read files before editing them

The Edit tool requires you to have Read the file in the same conversation before editing — this isn't just bureaucracy, it's how the tool prevents stale-anchor edits. Always:

```
Read /path/to/file
Edit /path/to/file ...
```

In sequence. Don't try to Edit based on memory of an earlier read.

### 5. Edit manifest BEFORE deleting cache dirs

Order matters:

1. Edit `installed_plugins.json` to remove the entry
2. THEN `rm -rf` the cache directory

If you delete the cache first, Claude Code may try to load the plugin on next start, find the cache missing, and produce confusing errors. Editing the manifest first cleanly de-registers the plugin; the cache deletion is just disk-space cleanup.

### 6. Restart-prompt at the end

Plugin changes don't take effect until Claude Code reads the manifest at session start. Always end with:

```
🔄 Restart Claude Code now (quit + relaunch) to load the trimmed config.
```

If the user is on Warp or another terminal multiplexer, mention that they need to fully exit Claude Code, not just close the tab.

## Plugin uninstallation — the anatomy

When you remove a plugin, you're removing:

1. **Manifest entry** — `~/.claude/plugins/installed_plugins.json` → `plugins.<key>`. This is the source of truth Claude Code reads at session start.
2. **Cache directory** — `~/.claude/plugins/cache/<marketplace>/<plugin-name>/<version>/`. Contains the actual plugin files (skills, agents, commands, hooks).
3. **Optionally**: orphaned MCP server registrations in user-scope settings. Most plugins ship their MCP servers via the plugin's own `plugin.json` — removing the manifest entry de-registers the MCP. But check `~/.claude/settings.json` and `~/.claude/settings.local.json` for `mcpServers` keys that might reference the plugin.

```bash
# Check for orphaned MCP server registrations
python3 -c "
import json
for f in ['/Users/<user>/.claude/settings.json', '/Users/<user>/.claude/settings.local.json']:
    try:
        with open(f) as fp: d = json.load(fp)
        servers = d.get('mcpServers', {})
        if servers:
            print(f'{f}: {list(servers.keys())}')
    except FileNotFoundError:
        pass
"
```

If anything shows up, ask the user before touching it.

## Standalone skill deletion — simpler

A standalone skill is just a directory at `~/.claude/skills/<name>/` containing a `SKILL.md`. Remove the directory and the skill is gone. No manifest, no cache, no MCP registrations to worry about.

```bash
rm -rf ~/.claude/skills/<name>
```

(After verifying the path exists, per rule 3.)

## Rules half — different but parallel

For the rules half:

- **Adding a new rule** — `Write` to `~/.claude/rules/<name>.md`. Reversible: `rm ~/.claude/rules/<name>.md`. Non-destructive of any existing data.
- **Editing an existing rule** — `Read` then `Edit`. The edit is reversible only via the user's version control or a manual revert. Show the old/new diff before applying when the change is significant.
- **Deleting a rule** — Same as standalone skill: `rm ~/.claude/rules/<name>.md`. Verify path first.
- **Editing CLAUDE.md** — Read first, edit precisely. The CLAUDE.md rule index is the most-read part of the file; mistakes here mislead the user every session.

## What if the user wants to "undo everything"

For plugins:

```bash
mv ~/.claude/plugins/installed_plugins.json.bak ~/.claude/plugins/installed_plugins.json
```

This restores the manifest. To restore deleted cache directories, the user needs to reinstall the plugins — there's no automatic cache restoration. Tell them so.

For standalone skills:

The skill directories are gone. If they want them back, they'd need to git-restore from a project the skills came from, or re-install them from wherever they originated.

For rules:

If the user has version control on `~/.claude/`, restore from there. Otherwise the changes are permanent.

This is why the safety protocol emphasises "show the plan before executing" — at that point the user can still say no.

## What we explicitly don't protect against

- **`rm -rf /` typos** — always use absolute paths starting with `~/.claude/` or `/Users/<user>/.claude/`. The skill never operates outside `~/.claude/`.
- **Symlink shenanigans** — if the user has symlinked their `~/.claude/` to somewhere unusual, the skill operates on the symlink target. We trust the user knows their setup.
- **Concurrent Claude Code sessions** — if the user has two Claude Code sessions open and runs the audit in one, the other will see stale config until restart. Mention this if you spot it.

## When in doubt, refuse

If a deletion plan looks weird (e.g. user says "delete everything", or the markdown report has zero items in Keep), stop and ask. Auto mode does not override "destructive operations need confirmation".
