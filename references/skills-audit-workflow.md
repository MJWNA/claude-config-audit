# Skills Audit Workflow

The detailed playbook for the skills+plugins half. Read this when you reach the skills audit phase.

## Phase 1 — Discovery

Run the prerequisite check + config inventory:

```bash
bash <skill-dir>/scripts/verify-prerequisites.sh
bash <skill-dir>/scripts/discover-config.sh
```

Capture two pieces of information:

1. **Plugin manifest** — read `~/.claude/plugins/installed_plugins.json` and extract every key
2. **Standalone skill directory** — list `~/.claude/skills/` (note: NOT `~/.claude/plugins/installed/` — that path is uncommon and was deprecated in Claude Code 1.x)

If the user has neither, stop here and tell them there's nothing to audit.

Also peek at session storage:

```bash
ls -d ~/.claude/projects/*/ 2>/dev/null | head -20
find ~/.claude/projects -name "*.jsonl" 2>/dev/null | wc -l
```

If the session count is < 50, warn the user that evidence will be thin — agents need session signal to give meaningful verdicts.

## Phase 2 — Categorise for parallel dispatch

Group the user's items into 4-6 logical buckets so each agent has a tight scope. Read the description of each plugin/skill (from its `plugin.json` or `SKILL.md`) and cluster by *purpose*, not by name. The right buckets depend entirely on what the user has installed.

Common purpose categories you can lean on (use whichever fit; ignore the rest):

- **Core dev tooling** — language servers, version control, doc lookup, debugging
- **Workspace / config / hooks** — bootstrap-style plugins, settings managers, automation hooks
- **Frontend / design** — UI tooling, asset pipelines, design references
- **Platform / infrastructure** — cloud providers, deployment, observability
- **Communications** — chat, email, ticket systems, notifications
- **Meta / skill authoring** — anything that helps the user write or improve their own skills/plugins
- **Domain-specific user skills** — custom skills the user has authored for their work

Don't force every category. If the user only has 10 items total, 2-3 buckets is enough. If they have 80 items, you may need more or different buckets — categorise by what's actually there.

## Phase 3 — Dispatch parallel agents

Send a single message with multiple `Agent` tool calls — one per bucket. The default `subagent_type` is `general-purpose` (always available). If specialised research subagents are installed (e.g. a `session-historian` from a research-oriented plugin), prefer those — they may know where Claude Code, Codex, and Cursor session storage live without prompting. If the user's `Agent` tool exposes a list, pick the most session-history-aware one available; otherwise fall back to `general-purpose`.

Each agent prompt should:

1. State the user's businesses/projects context (1-2 sentences) — agents need this to interpret usage signals
2. List the specific items in the bucket with their type
3. Tell the agent to count REAL invocations only — formal `Skill` tool calls + user-typed slash commands + relevant Bash patterns. Filter out skill-registry mentions (which appear in every system prompt).
4. Request a structured output: usage frequency, most recent date, evidence (1-2 examples), overlap analysis (does another tool do the same job better?), recommendation (KEEP/DELETE/MAYBE) with one-sentence reasoning
5. Set the time window (default: 90 days)

See `parallel-agent-patterns.md` for prompt templates.

## Phase 4 — Synthesise and build HTML

When agents return:

1. Merge findings into a single audit data array with this shape:

```js
{
  section: '📦 Plugins — <Bucket Name>',
  items: [
    {
      id: 'p-<plugin-key>',           // 'p-' prefix for plugins, 's-' for standalone skills
      name: 'plugin-name',
      type: 'plugin',                  // or 'standalone'
      verdict: 'keep',                 // 'delete' | 'maybe'
      invocations: '12 in 90d',        // include 🔥 emoji if usage is heavy
      mostRecent: '2026-04-25',
      desc: 'What it does',
      triggers: 'When it fires',
      notes: 'Caveats / overlap notes',
      evidence: 'Concrete examples from session history',
      agentReason: 'Why this verdict in 1-2 sentences',
      warn: 'overlap'                  // optional — see template comment for values
    }
  ]
}
```

2. Read the HTML template:

```bash
cat <skill-dir>/assets/skills-audit-template.html
```

3. Replace the `/* AUDIT_DATA_INJECTION_POINT */ []` placeholder with the populated array (everything from `[` to `]` — replace the example data, keep the comment)

4. Write the populated HTML to the user's CWD:

```
<user-cwd>/skills-audit.html
```

5. Tell the user:

> Open it: `open ./skills-audit.html`
>
> Walk through each card, mark Keep/Delete/Maybe, then click 📋 Generate Markdown and paste it back here.

Don't dump the full agent findings into chat. The HTML is the UI — chat is for the bookends.

## Phase 5 — Receive decisions

The user pastes the markdown report. Parse it without re-asking:

- Items under `## 🗑️ Delete` → for deletion
- Items under `## ✅ Keep` → leave alone
- Items under `## 🤔 Maybe` → flag for follow-up but don't act
- Items under `## ○ Undecided` → ask once if any are agent-strong-keeps (those are usually safe to default-keep)

Note the `## ⚠️ Where I overrode the agent` section if present — those overrides are the user's strongest signals about their preferences. Quote 1-2 of them back when summarising the plan, then move on.

## Phase 6 — Confirm the deletion plan

Before any destructive action, summarise concisely:

```
🗑️ X plugins to delete (manifest edit + cache rm):
  - plugin-a, plugin-b, plugin-c, ...

🗑️ Y standalone skills to delete (rm -rf):
  - skill-a, skill-b, ...

📦 Backup will be: ~/.claude/plugins/installed_plugins.json.bak

Reply 'go' (or 'go + <override>') to execute.
```

Do NOT proceed without explicit confirmation — even in auto mode, the destructive-action confirmation rule overrides "minimise interruptions".

## Phase 7 — Execute safely

Follow `safety-protocol.md`. The canonical sequence:

```bash
# 1. Backup
cp ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/installed_plugins.json.bak

# 2. Edit the manifest via Python (atomic, preserves all unrelated keys)
python3 <<PYEOF
import json
path = '/Users/<user>/.claude/plugins/installed_plugins.json'
with open(path) as f: d = json.load(f)
to_remove = ['plugin-a@marketplace', 'plugin-b@marketplace', ...]
for key in to_remove:
    d['plugins'].pop(key, None)
with open(path, 'w') as f: json.dump(d, f, indent=2)
print(f"Removed {len(to_remove)} plugins. Remaining: {len(d['plugins'])}")
PYEOF

# 3. Delete plugin cache directories
rm -rf ~/.claude/plugins/cache/<marketplace>/{plugin-a,plugin-b,...}

# 4. Delete standalone skill directories
# CRITICAL: verify path first
ls ~/.claude/skills/<skill-name>  # must succeed before rm
rm -rf ~/.claude/skills/{skill-a,skill-b,...}
```

Common mistake: `rm -rf` against a non-existent path silently succeeds. ALWAYS `ls` first when you're not 100% sure.

## Phase 8 — Verify

```bash
# Plugin count
python3 -c "import json; print(len(json.load(open('$HOME/.claude/plugins/installed_plugins.json'))['plugins']))"

# Skills count
ls ~/.claude/skills/ | wc -l

# List remaining
ls ~/.claude/skills/
```

Compare to expectations. Show the user the final state.

## Phase 9 — Restart prompt

Tell the user to restart Claude Code. The plugin manifest is read at session start; changes don't take effect until then.

```
Restart Claude Code (quit + relaunch from your terminal) to load the trimmed config.

After restart you should see:
  ✅ Smaller skill listing in system reminders
  ✅ Faster session startup
  ✅ No more <plugin-name> registration noise (if you removed it)
```

Mention the backup file. Tell them they can restore with:

```bash
mv ~/.claude/plugins/installed_plugins.json.bak ~/.claude/plugins/installed_plugins.json
```

(Note: deleted cache dirs would need plugin reinstall, which the manifest restore alone doesn't handle. Mention this if they care about full recoverability.)

## What success looks like

A real first-time audit on a 50-item install typically results in:

- ~30-50% items deleted (zero invocations in 90 days)
- 2-5 items moved to "maybe" (revisit in 30-90 days)
- 50-70% items kept (have invocation evidence)
- 1-3 user overrides of the agent (where the user has private context the agent missed)

If your audit produces "keep everything" or "delete everything" verdicts, something went wrong — the agents probably didn't have enough signal. Re-check session history depth.
