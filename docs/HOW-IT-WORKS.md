# How It Works — Detailed Walkthrough

What actually happens when a user runs `claude-config-audit`. Each phase, each tool, each file touched.

## Phase 0 — Trigger

The skill activates one of three ways:

1. **Slash command** — `/audit-skills` or `/audit-rules`. This is the most reliable trigger and skips the "which half" prompt.
2. **Description match** — the user says something like "audit my Claude config", "clean up my skills", "spring clean Claude". The description in `SKILL.md` covers the common phrasings.
3. **Manual** — `Skill` tool invocation by name from another agent.

The skill loads its `SKILL.md` into context. The references files don't load yet — they're progressive-disclosed when the skill reaches the corresponding phase.

## Phase 1 — Prerequisite check

```bash
bash <skill-dir>/scripts/verify-prerequisites.sh
```

Verifies:

- `~/.claude/` exists (Claude Code installed)
- At least one auditable surface is present: plugin manifest, standalone skills, user-scope rules, hooks/MCP settings, or project-scope config in `$PWD/.claude/`
- `python3` is available (used for atomic JSON edits and the audit-history script)
- CWD is writable (HTML lands here)
- Session-history depth — warns if < 50 sessions (verdicts will be biased toward "looks underused")
- Pending quarantine — warns if there's an unresolved quarantine session from a previous run

If anything fails the skill stops and reports. Otherwise it proceeds.

## Phase 2 — Discovery

```bash
bash <skill-dir>/scripts/discover-config.sh           # user-scope only
bash <skill-dir>/scripts/discover-config.sh --project # adds $PWD/.claude/
```

The discovery script inventories:

- Plugins in `installed_plugins.json` (key, version, install date)
- Standalone skills under `~/.claude/skills/` (with description from each `SKILL.md`)
- User-scope rules under `~/.claude/rules/` (size + frontmatter status)
- Hook handlers + MCP servers (count only — settings.json is read but never modified at this stage)
- Session history depth + oldest session date
- Audit history (any previous audit's decisions on file)
- Quarantine status (anything pending restore from previous runs)

## Phase 3 — Decision memory check

If `~/.claude/.audit-history/` exists, the skill reads the most recent audit's decisions:

```bash
python3 <skill-dir>/scripts/audit-history.py latest skills
python3 <skill-dir>/scripts/audit-history.py diff skills <current-items.json>
```

The diff produces three groups:

- **new** — items not present in the previous audit (e.g. plugins installed since)
- **gone** — items present last time but missing now (e.g. uninstalled outside the audit)
- **changed** — items whose evidence has shifted (e.g. invocation count rose from 0 to 5)

For audits with previous history, the skill surfaces only these in the HTML, with stable items rolled up under a "kept since last audit" collapsed section. First audits surface everything.

## Phase 4 — Skills audit half (if chosen)

### 4a. Categorise

The skill reads each plugin/skill description and clusters by *purpose* — see `references/skills-audit-workflow.md` for the bucket categories. The exact buckets depend on what the user has installed; the skill does not assume specific items exist.

### 4b. Dispatch parallel agents

In a single message, the skill dispatches:

- 4-5 bucket agents (one per category) — each scans session history for usage patterns of items in its bucket
- 1 security-pass agent — scans hooks for shell injection, MCPs for suspicious endpoints, settings for hardcoded tokens, skills for over-broad `allowed-tools`

Each agent gets a structured prompt (see `references/parallel-agent-patterns.md`) and returns structured findings.

The skill picks the best available `subagent_type` at runtime. `general-purpose` is always available; specialised research subagents (if installed) are preferred.

### 4c. Synthesise

When agents return, the skill builds the audit data array. Each item carries:

```js
{
  id: '<stable-slug>',
  name: '<display-name>',
  type: 'plugin' | 'standalone',
  verdict: 'keep' | 'delete' | 'maybe',
  confidence: 'high' | 'medium' | 'low',     // NEW in v2
  reasonCodes: ['zero-usage-90d', ...],      // NEW in v2 — short tags
  invocations: '<human-readable>',
  mostRecent: '<date or "Never">',
  desc: '<what it does>',
  triggers: '<when it fires>',
  evidence: '<concrete examples from sessions>',
  agentReason: '<one paragraph reasoning>',
  warn: 'overlap' | 'duplicate' | 'one-shot' | undefined,
  previousDecision: { decision, note, date } | undefined  // NEW in v2 — populated from audit history
}
```

### 4d. Build HTML

The skill reads `assets/skills-audit-template.html`, replaces the `/* AUDIT_DATA_INJECTION_POINT */ []` placeholder with the populated array, and writes to user's CWD as `skills-audit.html`.

The HTML uses `escapeHtml()` on every interpolation that comes from agent output, so audit data containing HTML-shaped strings cannot inject script.

### 4e. User reviews

In their browser:

1. Each item is a card with verdict badge, confidence chip, invocation count, evidence quotes
2. Items with `previousDecision` show a "📚 Last audit: you chose X — <reason>" hint inline
3. "Apply all agent verdicts" bulk-loads recommendations
4. The user walks through cards, overrides where they disagree
5. Filters help: "Show undecided", "Show mismatches"
6. "Generate Markdown" exports a structured report including a JSON envelope at the end (used by audit-history)

### 4f. Receive decisions + confirm

The user pastes the markdown back. The skill parses the section structure for decisions and shows the deletion plan:

```
🗑️ X plugins to quarantine (manifest edit + cache mv to quarantine session)
🗑️ Y standalone skills to quarantine (mv, not rm -rf)
🔐 Z security findings to address
📦 Quarantine session will be: ~/.claude/.audit-quarantine/<ISO-timestamp>/

Reply 'go' to execute.
```

Auto mode does NOT bypass this gate. The cost of one extra round-trip is small.

### 4g. Execute via quarantine

```bash
SESSION=$(bash <skill-dir>/scripts/quarantine.sh init)

# Backup the manifest (copy, don't move — Claude Code still needs it)
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/plugins/installed_plugins.json --copy

# Edit the manifest atomically via Python
python3 -c "<atomic edit>"

# MOVE plugin cache dirs into the quarantine
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/plugins/cache/<marketplace>/<plugin>/

# MOVE standalone skill dirs into the quarantine
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/skills/<skill-name>/

# Write the manifest with restore instructions
bash <skill-dir>/scripts/quarantine.sh manifest "$SESSION"
```

Nothing is `rm -rf`'d. Everything is recoverable for 7 days. Run `quarantine.sh purge` after the TTL elapses (or manually if the user is confident).

### 4h. Save decisions

```bash
python3 <skill-dir>/scripts/audit-history.py save skills <markdown-path>
```

Persists the user's decisions to `~/.claude/.audit-history/<ISO-timestamp>--skills.json` for the next audit.

### 4i. Restart prompt

```
Restart Claude Code (quit + relaunch) to load the trimmed config.

After restart you should see:
  ✅ Smaller skill listing
  ✅ Faster session startup
  ✅ Slimmer slash command list

If anything's wrong:
  bash <skill-dir>/scripts/restore.sh <quarantine-session>
```

## Phase 5 — Rules audit half (if chosen)

The rules half is structurally similar but uses 4 distinct agent types plus the security-pass agent. Each agent has a different deliverable rather than a different bucket. See `docs/HOW-IT-WORKS.md` references and `references/rules-audit-workflow.md` for the full sequence.

The key v2 changes for the rules half:

- The markdown export is **self-contained** — it includes the full `proposedContent` for new rules and the full `proposedSnippet` for extensions inline. The execution step doesn't depend on Claude remembering scrollback.
- Before any edit, `CLAUDE.md` and the rules directory are **snapshotted to the same quarantine session** that the skills half used (or a new one if running rules-only). Rule edits are reversible from quarantine, not just "use your own version control" as in v1.
- The official-spec agent's findings populate the HTML's spec-primer section, so the user can review it inline rather than reading the spec separately.

## Phase 6 — Wrap up

The skill offers (once, not pushing):

- A scheduled re-audit (if the user has a `/schedule`-style mechanism available)
- Restore-from-quarantine instructions if they're still uncertain
- A document of the audit results somewhere persistent (handoff doc, decision log)

## What's in each file at runtime

| File | Loaded when |
|---|---|
| `SKILL.md` | Skill triggers |
| `references/skills-audit-workflow.md` | Starting the skills half |
| `references/rules-audit-workflow.md` | Starting the rules half |
| `references/parallel-agent-patterns.md` | Dispatching agents |
| `references/safety-protocol.md` | Before any destructive action |
| `references/claude-config-spec.md` | Rules audit needs to discuss frontmatter / spec |
| `assets/*-audit-template.html` | Read, populated, written to user's workspace |
| `scripts/*.sh`, `scripts/*.py` | Executed via Bash |

## Total round-trips for a typical run

- 1 turn: trigger
- 1 turn: prerequisite + discovery + history check
- 1 turn: dispatch skills agents (parallel — multiple Agent calls in one turn)
- ~5 turns: agent completion notifications (one per agent, async)
- 1 turn: synthesise + build skills HTML
- (User reviews — out of band, 20-30 min)
- 1 turn: receive markdown, confirm plan
- 1 turn: execute via quarantine + save decisions
- 1 turn: dispatch rules agents (parallel)
- ~5 turns: agent completion notifications
- 1 turn: synthesise + build rules HTML
- (User reviews — out of band, 20-30 min)
- 1 turn: receive markdown, confirm plan
- 1 turn: execute rule changes (with quarantine snapshot first) + save decisions

Total: ~15 turns + agent runtime + user review time. Most of the wall-clock cost is the user reviewing in the browser, which is exactly the work that requires their judgment.
