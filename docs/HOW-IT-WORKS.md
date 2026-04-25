# How It Works — Detailed Walkthrough

What actually happens when a user runs `claude-config-audit`. Each phase, each tool, each file touched.

## Phase 0 — Trigger

User says something like "audit my Claude config" / "clean up my skills" / "spring clean Claude". Per the SKILL.md description's deliberately-pushy triggering, Claude invokes the skill.

The skill loads its SKILL.md into context. The references files don't load yet — they're progressive-disclosed.

## Phase 1 — Prerequisite check

Claude runs `scripts/verify-prerequisites.sh`:

```bash
bash <skill-dir>/scripts/verify-prerequisites.sh
```

This checks:

- `~/.claude/` exists (Claude Code installed)
- At least one of `~/.claude/plugins/installed_plugins.json`, `~/.claude/skills/`, or `~/.claude/rules/` is populated
- `python3` and `ls` available
- CWD is writable (HTML lands here)

If anything fails, the skill stops and reports. Otherwise it proceeds.

## Phase 2 — Discovery

Claude runs `scripts/discover-config.sh` to inventory:

- Plugins in `installed_plugins.json` (key, version, install date)
- Standalone skills under `~/.claude/skills/` (with description from each SKILL.md)
- User-scope rules under `~/.claude/rules/` (with size + frontmatter status)
- Session history depth (count of `.jsonl` files in `~/.claude/projects/`)

This data informs which audit halves to offer:

- Plugins or skills present → skills audit half is relevant
- Rules present → rules audit half is relevant

Claude shows the summary and asks if they want both halves or one.

## Phase 3 — Skills audit half (if chosen)

### 3a. Categorise

Claude reads each SKILL.md's description and groups items into 4-6 buckets. Common buckets:

- Core dev tooling (LSP, version control, doc lookup)
- Workspace / hooks
- Frontend / design
- Platform / infrastructure
- Communications
- Meta / skill-authoring
- Domain-specific user skills

The categorisation is heuristic. Claude can re-categorise on the fly if needed.

### 3b. Dispatch parallel agents

Claude reads `references/parallel-agent-patterns.md` and `references/skills-audit-workflow.md` for prompt templates.

Then dispatches in a single message:

```
Agent({ subagent_type: 'compound-engineering:research:session-historian',
        prompt: '...skills audit prompt for bucket 1...' })
Agent({ subagent_type: 'compound-engineering:research:session-historian',
        prompt: '...skills audit prompt for bucket 2...' })
... (one per bucket)
```

Each agent:

- Searches `~/.claude/projects/*.jsonl` for tool_use entries
- Counts formal Skill calls, slash commands, Bash patterns
- Returns a structured report per item with frequency / recency / evidence / verdict

The agents work in parallel. Claude waits for completion notifications.

### 3c. Synthesise

When all agents return, Claude builds the audit data array. Each item becomes:

```js
{
  id: 'p-context7',
  name: 'context7',
  type: 'plugin',
  verdict: 'keep',
  invocations: '220 in 90d 🔥',
  mostRecent: '2026-04-25 (today)',
  desc: 'Library docs lookup MCP',
  triggers: 'Per context7-docs.md rule',
  notes: '',
  evidence: '163 query-docs + 57 resolve-library-id calls across 51 sessions',
  agentReason: 'Highest-value plugin in the audit by a wide margin.'
}
```

### 3d. Build HTML

Claude reads the template (`assets/skills-audit-template.html`), replaces the `/* AUDIT_DATA_INJECTION_POINT */ []` placeholder with the populated data array, and writes to user's CWD as `skills-audit.html`.

Claude tells the user:

> Open it: `open ./skills-audit.html`

### 3e. User reviews

In their browser, the user:

1. Sees a card per item with verdict badge, invocation count, evidence
2. Clicks "Apply all agent verdicts" to bulk-load recommendations
3. Walks through cards, overrides where they disagree
4. Optionally: filters to "Show undecided" or "Show mismatches"
5. Clicks "Generate Markdown" → copies the output

### 3f. Receive decisions

User pastes the markdown. Claude parses:

- `## 🗑️ Delete` items → for deletion
- `## ✅ Keep` items → leave alone
- `## 🤔 Maybe` items → flag for follow-up
- `## ⚠️ Where I overrode the agent` → note the user's preferences

### 3g. Confirm + execute

Claude reads `references/safety-protocol.md`. Then:

1. Shows the deletion command list
2. Waits for "go"
3. Backs up `installed_plugins.json` → `.bak`
4. Edits the manifest via Python (atomic)
5. `rm -rf` the cache directories (after `ls` verification)
6. `rm -rf` the standalone skill directories (after `ls` verification)
7. Verifies final state

### 3h. Restart prompt

Claude tells the user to quit and relaunch Claude Code. Notes the backup file path.

## Phase 4 — Rules audit half (if chosen)

### 4a. Read every rule file in full

Claude reads each file in `~/.claude/rules/`. Also reads `~/.claude/CLAUDE.md` for the rule index.

Lists project-scope rule directories if any (for the codebase-pattern-scan agent).

### 4b. Dispatch 4 parallel agents

Different agent types this time, each with a distinct deliverable:

- **Existing rules audit** (`compound-engineering:research:repo-research-analyst`) — per-rule frontmatter + quality assessment + classification mismatch list
- **Codebase pattern scan** (`compound-engineering:research:repo-research-analyst`) — candidate new rules from cross-project pattern repetition
- **Official spec lookup** (`compound-engineering:research:framework-docs-researcher`) — current Claude Code rule frontmatter spec + known parser bugs
- **Session-history archaeology** (`compound-engineering:research:session-historian`) — candidate new rules from repeated corrections / explanations / endorsements

### 4c. Synthesise

Claude builds five arrays:

- `existingRules` — per-rule cards with what-it-does / when-it-fires / why-it-exists / without / quality / issues / actionItems / agentReason / refresh-value
- `mismatches` — CLAUDE.md classification fixes
- `newRules` — candidate new rule files **with full proposed content** (not just sketches)
- `extensions` — small additions to existing rules with location + snippet
- `refreshes` — keyed by existing-rule id, each with value/scope/benefit for the "🔥 refresh" decision option

### 4d. Build HTML

Same process as skills-audit-template, but using `assets/rules-audit-template.html`.

### 4e. User reviews + decides

User walks through 4 sections (existing rules, mismatches, new candidates, extensions). For each existing rule, the "Potential refresh" section shows what a refresh would entail and the value rating (low/medium/high).

User generates markdown, pastes back.

### 4f. Execute

Order of operations:

1. Write all new rule files (parallel)
2. Read each existing rule that needs editing
3. Edit each existing rule (extensions or refreshes)
4. Read CLAUDE.md
5. Edit CLAUDE.md to fix classifications + add new rule index entries

### 4g. Verify

```bash
ls ~/.claude/rules/
wc -l ~/.claude/rules/*.md
```

Claude shows the final inventory.

### 4h. Restart prompt + smoke tests

Claude lists smoke-test ideas — one per new rule — so the user can verify the rules are firing in the next session.

## Phase 5 — Wrap up

Claude offers to:

- `/schedule` a quarterly re-run reminder
- Update HANDOFF.md (if the user has a session-continuity skill)
- Document the audit results somewhere persistent

## What's in each file at runtime

- **`SKILL.md`** — loaded when the skill triggers
- **`references/skills-audit-workflow.md`** — loaded when starting the skills half
- **`references/rules-audit-workflow.md`** — loaded when starting the rules half
- **`references/parallel-agent-patterns.md`** — loaded when dispatching agents
- **`references/safety-protocol.md`** — loaded before any destructive action
- **`references/claude-config-spec.md`** — loaded when the rules audit needs to discuss frontmatter / spec
- **`assets/skills-audit-template.html`** — read, populated, written to user's workspace
- **`assets/rules-audit-template.html`** — read, populated, written to user's workspace
- **`scripts/*.sh`** — executed as Bash commands

## Total round-trips

For a typical run:

- 1 turn: trigger
- 1 turn: prerequisite + discovery
- 1 turn: dispatch skills agents (parallel — 5 agent calls in one turn)
- ~5 turns: agent completion notifications (one per agent, async)
- 1 turn: synthesise + build skills HTML
- (User reviews — out of band, however long they take)
- 1 turn: receive markdown, confirm plan
- 1 turn: execute deletions
- 1 turn: dispatch rules agents (parallel — 4 agent calls in one turn)
- ~4 turns: agent completion notifications
- 1 turn: synthesise + build rules HTML
- (User reviews — out of band)
- 1 turn: receive markdown, confirm plan
- 1 turn: execute rule changes

Total: ~15 turns + agent runtime + user review time. Most of the wall-clock cost is the user reviewing in the browser, which is exactly the work that requires their judgment.
