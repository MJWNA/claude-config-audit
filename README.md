# claude-config-audit

> **Evidence-based audit + cleanup for Claude Code installations.** Decide what to keep, delete, or refresh across plugins, skills, and rules — grounded in your actual session history, not generic recommendations.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-7c3aed.svg)](https://docs.claude.com/en/docs/claude-code)
[![Status](https://img.shields.io/badge/Status-Production%20Ready-22c55e.svg)]()

A production-ready Claude Code skill that scans your installation, dispatches parallel sub-agents to evaluate usage from your own session history, generates two interactive HTML decision tools, and safely executes the cleanup you choose.

---

## 🎯 Why this exists

Your Claude Code installation is probably bloated. Mine was. Here's how it happens:

You install a plugin to try a feature. It works for that one task, then sits there forever. You add a custom skill in a moment of inspiration — never invoke it again. You write a user-scope rule from a single correction, and three months later it's still loading on every session even though the situation never recurred. **Nothing ever gets removed.**

Six months later you've got 50+ plugins and skills and rules, and you can't remember which ones actually pull weight. The slash command list takes a second to scroll. Your context window starts every session preloaded with skill descriptions you'll never trigger. You feel vaguely guilty about it but the prospect of making 50 keep/delete decisions is paralysing.

**This skill fixes that — once, properly, with evidence.**

It looks at your actual session history (the `.jsonl` files Claude Code writes for every session) and counts which plugins, skills, and rules you've actually invoked in the last 90 days. Then it presents the findings in a clean interactive UI so you can sweep through 50 items in 30 minutes instead of 3 hours.

After: your install is leaner. Sessions start faster. Your slash command list is the things you actually use. Your `~/.claude/rules/` is the rules that genuinely prevent mistakes, not the ones you forgot you wrote.

---

## ✨ What you get

When you run this skill, by the end of the session you have:

| Outcome | Detail |
|---|---|
| 📊 **Two evidence reports** | One per audit half — counts of real invocations, recency, overlap analysis, per-item verdicts |
| 🎨 **Two interactive HTML decision tools** | Saved to your workspace with your actual config pre-loaded — review, decide, export |
| 📝 **A markdown summary** | Of every decision, with your overrides highlighted, that you can paste back to chat |
| 🧹 **A cleaner installation** | Plugins/skills you don't use deleted, rules updated, CLAUDE.md restructured |
| 💾 **Safety backups** | Original `installed_plugins.json` preserved, every action shown before execution |
| 🔄 **A restart prompt** | With smoke-test ideas to verify the changes work in your next session |

### Example outcome (from a real audit)

**Before:** 25 plugins + 25 standalone skills + 14 rules = **64 items**
**After:** 12 plugins + 20 skills + 21 rules = **53 items**

Net: cut 18 unused items, added 7 new evidence-based rules, fixed 5 misclassified rules. About 1 hour of focused work.

---

## 🚀 Quickstart

### 1. Install

```bash
git clone https://github.com/MJWNA/claude-config-audit.git ~/.claude/skills/claude-config-audit
```

### 2. Restart Claude Code

The skill becomes available after restart. Claude Code reads `~/.claude/skills/` at session start.

### 3. Trigger it

In any project, just say:

> Audit my Claude config

or any of these phrases:

- "Clean up my skills"
- "Which plugins should I delete"
- "Spring clean Claude"
- "Audit my rules"
- "What plugins am I actually using"
- "Trim my Claude install"

The skill description has 16+ trigger phrases — it's deliberately easy to invoke.

### 4. Walk through

Claude will:

1. Run a prerequisite check + inventory your install
2. Ask if you want both audit halves or just one (most users want both)
3. Dispatch parallel sub-agents to scan your session history
4. Generate the HTML decision tools (saved to your current directory)
5. Tell you to open them: `open ./skills-audit.html`
6. Wait for your decisions (you click through cards in the browser)
7. Receive your markdown export when you paste it back to chat
8. Show you the exact deletion commands and ask for "go"
9. Execute the cleanup with backups
10. Prompt you to restart Claude Code

Total time: ~30-60 minutes for a first-time audit, ~10-15 minutes thereafter.

---

## 🧭 What the skill audits

It splits your installation into two halves, each run independently or in sequence:

### Half 1 — Skills audit

Targets the **executable layer**:

- **Plugins** — anything in `~/.claude/plugins/installed_plugins.json`
- **Standalone skills** — directories under `~/.claude/skills/`

For each item the skill answers: *did the user actually invoke this in the last 90 days?* Items with zero invocations get a strong DELETE verdict; items with high invocation counts get a strong KEEP. Items in the middle (a few invocations, used recently, overlaps with another tool) get MAYBE.

The cleanup deletes plugins via manifest edit + cache directory removal, and deletes skills via `rm -rf <skill-dir>`.

### Half 2 — Rules audit

Targets the **instruction layer**:

- **User-scope rules** under `~/.claude/rules/`
- **The CLAUDE.md rule index** (the table that documents which rules load when)

Rules don't get "invoked" the way skills do — they load passively into context. So this half asks different questions:

- Is the content fresh, or does it reference deleted skills/projects?
- Is the frontmatter correct (per the official Claude Code spec)?
- Does the CLAUDE.md index match actual loading behaviour?
- Are there cross-project patterns that should be promoted to user-scope?
- Are there session-history patterns (corrections you keep giving Claude) that should be encoded as rules?

Outcome: writes new rule files, edits existing ones, restructures the CLAUDE.md rule index.

**You can run either half on its own** — say "just audit my plugins" or "just audit my rules" — but most users benefit from both.

---

## 🎬 What it looks like

When you trigger the skill, here's what the conversation looks like (abbreviated):

> **You:** "Audit my Claude config"
>
> **Claude:** Running prerequisite check… ✅ Found 25 plugins, 25 standalone skills, 21 user-scope rules, 1,995 sessions in history. Want both halves or just one?
>
> **You:** "Both"
>
> **Claude:** Starting skills audit. Dispatching 5 parallel agents to scan your session history…
>
> *(60 seconds pass — agents work in parallel)*
>
> **Claude:** All 5 agents back. Built `./skills-audit.html` with your actual config pre-loaded. **Open it: `open ./skills-audit.html`**. Click "Apply all agent verdicts" to bulk-load recommendations, walk through each card, then paste the generated markdown back here.

You then open the HTML, see something like this for each plugin/skill:

```
┌────────────────────────────────────────────────────────────────────────┐
│ ▶ figma                                                                │
│   plugin · 🤖 🗑️ DELETE · 📊 0 in 90d                                  │
│                                              [✅ keep] [🗑️ delete] [🤔]│
├────────────────────────────────────────────────────────────────────────┤
│ What: 5 skills (generate-design, implement-design...) + figma MCP      │
│ Most recent: Never                                                     │
│ Evidence: mcp__plugin_figma_figma__authenticate appears 334× in raw    │
│           grep, but ALL system-prompt tool definitions, NEVER actually │
│           called. Zero real tool_use entries.                          │
│ 🤖 Agent verdict: DELETE                                               │
│ Five skills + an MCP server with zero traction. Pure context bloat —   │
│ figma authenticates on every session-start but is never used.          │
└────────────────────────────────────────────────────────────────────────┘
```

You make decisions, hit **📋 Generate Markdown**, paste back. Claude shows the deletion plan, you say "go", it executes. Done.

The full sample output of a real audit is in [`examples/sample-audit-output.md`](examples/sample-audit-output.md).

---

## 🏗️ How it works (technical breakdown)

For readers who want to know exactly what's happening under the hood.

### Architecture

```
Trigger (user phrase)
  ↓
SKILL.md loaded into Claude's context
  ↓
Phase 1: Prerequisite check (scripts/verify-prerequisites.sh)
  ↓
Phase 2: Discovery (scripts/discover-config.sh)
  ↓
Phase 3: Categorise items into 4-6 buckets per audit half
  ↓
Phase 4: Dispatch parallel sub-agents (5 for skills, 4 for rules)
  ↓                                    ↓
  Each agent reads session             Each rules-half agent has
  history JSONL files at               a distinct purpose:
  ~/.claude/projects/                  - Existing rules quality audit
                                       - Codebase pattern scan
  Counts real Skill tool calls,        - Official spec lookup
  user slash commands, MCP             - Session-history archaeology
  invocations, Bash patterns
  ↓                                    ↓
Phase 5: Synthesise findings into HTML data array
  ↓
Phase 6: Read HTML template, inject data, save to user's CWD
  ↓
[USER REVIEWS IN BROWSER — outside chat]
  ↓
Phase 7: User pastes markdown export
  ↓
Phase 8: Confirm deletion plan, get "go"
  ↓
Phase 9: Execute (manifest edit, rm -rf, file writes/edits)
  ↓
Phase 10: Verify + restart prompt
```

### The parallel-agent pattern

Sequential analysis of 50 items in a single agent would:

- Fill the context window quickly
- Take 10x longer
- Lose precision (later items get less attention than earlier ones)
- Mix categories and ruin overlap analysis

Independent agents per bucket finish in parallel and each keeps a tight context. The skill dispatches them in a single message with multiple `Agent` tool calls — they all run concurrently and return in any order.

The skills-audit agents share one prompt template (varies by item list). The rules-audit agents have four distinct prompts (existing-rules audit, codebase pattern scan, official spec lookup, session-history archaeology) because they have distinct deliverables.

Full prompt templates: [`references/parallel-agent-patterns.md`](references/parallel-agent-patterns.md).

### Session-history evidence sources

The agents look for:

| Signal | Where |
|---|---|
| Formal `Skill` tool calls | `tool_use` blocks with `"skill":"<name>"` in JSONL |
| User-typed slash commands | `<command-name>/<name></command-name>` tags in user messages |
| MCP tool invocations | `tool_use` with names like `mcp__<plugin>__<tool>` |
| Bash command patterns | `tool_use` with bash content matching skill-relevant patterns |
| Subagent dispatches | `Task` tool calls with matching `subagent_type` |

It explicitly does NOT count:

- Skill descriptions appearing in `<system-reminder>` skill registries (those appear in every recent session, regardless of usage)
- Mentions of the skill name in user prompts that don't actually trigger it

This filtering is critical — without it, every item would look "frequently invoked" because skill registries appear in 99% of sessions.

### The HTML decision tools

Each half has a dedicated HTML template in `assets/`. They share design language but have different decision UIs:

- **`skills-audit-template.html`** — three-way decisions (Keep/Delete/Maybe), single section per category bucket, expandable rule cards with verdict badges and invocation counts
- **`rules-audit-template.html`** — five sections (existing rules, classification mismatches, new candidates, extensions, spec primer), more decision options per section type, plus an inline "Potential refresh" panel with low/medium/high value rating

Both templates are **self-contained single-file apps**:

- Vanilla JavaScript — no React, no framework, no build step
- Vanilla CSS — no preprocessor
- localStorage persistence — your decisions survive page reloads
- No external assets — works offline

The data injection point is documented in the template's HTML comment:

```html
<!--
  HOW TO USE THIS TEMPLATE:
  1. Locate the AUDIT_DATA_INJECTION_POINT marker in the <script> tag
  2. Replace `[]` with your populated audit data array
  3. Save to user's CWD as skills-audit.html or rules-audit.html
  4. Tell the user: open ./skills-audit.html
-->
```

The data shape is documented inline so you (or anyone customising the skill) can build the data array correctly.

### Safety protocol

This is a destructive workflow — it modifies user-scope config that affects every Claude Code session. The safety rails:

| Rail | Implementation |
|---|---|
| Backup before manifest edit | `cp ~/.claude/plugins/installed_plugins.json{,.bak}` |
| Path verification before `rm -rf` | Always `ls` first; skip if path doesn't exist |
| Manifest edit before cache deletion | Order matters — manifest first, then cache |
| Read before edit | Edit tool's anchor-string matching requires prior Read |
| Confirmation gate | Even in auto mode, deletion commands shown before execution |
| Restart prompt | Plugin manifest read at session start; changes need restart |

Full detail: [`references/safety-protocol.md`](references/safety-protocol.md). What can and can't be undone: [`docs/SAFETY.md`](docs/SAFETY.md).

### Files modified

The skill operates strictly within `~/.claude/`:

| Path | Operation |
|---|---|
| `~/.claude/plugins/installed_plugins.json` | Edit (Python-based, atomic) — preserves all unrelated keys |
| `~/.claude/plugins/installed_plugins.json.bak` | Created automatically before any edit |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/` | `rm -rf` after manifest update |
| `~/.claude/skills/<skill-name>/` | `rm -rf` for deleted standalone skills |
| `~/.claude/rules/*.md` | `Write` (new rules) and `Edit` (existing rules) |
| `~/.claude/CLAUDE.md` | `Edit` (rule index updates) |

Nothing outside `~/.claude/` is touched. Project-scope `.claude/` directories are untouched. Settings files (`settings.json`, `settings.local.json`) are read-only — modified only when MCP server cleanup is needed and only after explicit confirmation.

### Repository layout

```
claude-config-audit/
├── SKILL.md                         # Main skill — frontmatter + workflow guide
├── README.md                        # This file
├── LICENSE                          # MIT
├── CHANGELOG.md
├── .gitignore
├── assets/
│   ├── skills-audit-template.html   # Self-contained HTML for skills decisions
│   └── rules-audit-template.html    # Self-contained HTML for rules decisions
├── references/
│   ├── skills-audit-workflow.md     # 9-phase playbook for the skills half
│   ├── rules-audit-workflow.md      # 9-phase playbook for the rules half
│   ├── parallel-agent-patterns.md   # Prompt templates for all agents
│   ├── claude-config-spec.md        # Official Claude Code rule spec + bug citations
│   └── safety-protocol.md           # Backup/rollback procedures
├── scripts/
│   ├── verify-prerequisites.sh      # Sanity check before audit
│   └── discover-config.sh           # Inventory current install
├── docs/
│   ├── PHILOSOPHY.md                # Why this skill exists
│   ├── HOW-IT-WORKS.md              # Detailed phase-by-phase walkthrough
│   ├── SAFETY.md                    # What's modified, what's not, recovery
│   └── EXTENDING.md                 # Customisation guide
└── examples/
    └── sample-audit-output.md       # Real-world audit results
```

The `references/` files use Claude Code's progressive disclosure pattern — they're not loaded into context until Claude reaches the corresponding phase. This keeps `SKILL.md` itself under 300 lines while still giving Claude detailed playbooks when needed.

---

## ❓ FAQ

### How is this different from running `/plugin` and uninstalling things one at a time?

`/plugin` is the right tool for installing and managing individual plugins. This skill is for the audit moment — when you're staring at 50 items and asking "which 18 of these should go?" Different problem, different tool.

The audit is also evidence-based: you don't just delete things you "feel like you don't use" — you delete things you provably haven't invoked.

### Will this delete my session history?

No. The skill **reads** session history from `~/.claude/projects/` to count invocations, but never modifies it. Your sessions are safe.

### What if I'm on Claude.ai (web), not Claude Code (CLI)?

This skill needs Claude Code's parallel sub-agent dispatch and Bash access — neither is available on Claude.ai. The skill won't run there. The good news: Claude.ai doesn't accumulate plugins/skills/rules the same way, so you don't need it.

### What if my session history has been pruned?

The agents need session signal to give meaningful verdicts. If your `~/.claude/projects/` has fewer than ~50 sessions, the prerequisite check warns you that evidence will be thin and verdicts may be biased toward "looks underused." A fresh install with 10 sessions probably isn't worth auditing yet.

### Can I customise the categories or HTML?

Yes. Both are template-driven. See [`docs/EXTENDING.md`](docs/EXTENDING.md). The HTML uses vanilla JS/CSS so changes are direct file edits — no build step.

### How long does this take?

| Stage | Typical time |
|---|---|
| Prerequisite check + discovery | ~30 seconds |
| Parallel agent execution (skills half) | ~60-180 seconds |
| User reviews HTML and makes decisions | ~20-30 minutes for 50 items |
| Cleanup execution | ~30 seconds |
| Parallel agent execution (rules half) | ~120-300 seconds |
| User reviews rules HTML | ~20-30 minutes |
| Rules cleanup execution | ~60 seconds |
| **Total** | **~60 minutes for a first-time audit** |

Most of the wall-clock time is you reviewing in the browser, which is exactly the work that requires your judgment.

### What if I don't trust the agent's verdicts?

The HTML shows you the evidence (invocation count, dates, concrete examples) before you decide. Override anything you disagree with. The skill captures your overrides in a "Where I overrode the agent" section of the markdown export — useful audit trail, and signals to future-you which patterns the agents got wrong.

### Will it work in a fresh Claude Code install?

Technically yes, but practically no — there's nothing to audit. Run it after you've been using Claude Code for a few months and have accumulated stuff.

### Does it support project-scope rules (`<project>/.claude/rules/`)?

The rules-audit-half **reads** project-scope rules to identify cross-project patterns that should be promoted to user-scope, but does NOT modify them. They're considered project-owned. If you want to clean up project-scope rules, do that per-project.

### What if the agents disagree with each other?

For the rules half, the four agents have distinct deliverables, so they don't directly disagree. For the skills half, agents are categorised (no overlap in items between buckets) so they also don't disagree. The synthesis step combines findings, not opinions.

### Can I run this on a CI server?

Not really — the workflow needs interactive HTML review. You can run the discovery and agent phases headlessly, but the decision phase requires a human in the loop. This is intentional: keep/delete decisions about your own config aren't a fit for autopilot.

### What's the absolute minimum useful run?

If you want a quick taste:

```
"Audit just my plugins, no agents, just list zero-invocation ones"
```

The skill will skip the parallel-agent phase and just run the discovery + show you a list of plugins/skills with no recent invocations. ~5 minutes, no review UI. Useful as a sanity check before committing to a full audit.

---

## 🛠️ Customising

The skill is opinionated about workflow but flexible about content. Customisation guide: [`docs/EXTENDING.md`](docs/EXTENDING.md).

Quick pointers:

| Want to change | Edit |
|---|---|
| Agent prompts | `references/parallel-agent-patterns.md` |
| Categorisation buckets | `references/skills-audit-workflow.md` |
| HTML styling | `assets/*-audit-template.html` (CSS at top) |
| Markdown output format | The `generateMarkdown()` function in each HTML template |
| Time window (default 90d) | Find every "90 days" in `references/*.md` |
| Prerequisite checks | `scripts/verify-prerequisites.sh` |

---

## 🗺️ Roadmap

Possible future enhancements (not promises):

- [ ] **Project-scope rules audit** — same workflow but for `<project>/.claude/rules/` instead of user-scope
- [ ] **Settings.json audit** — review and clean up `~/.claude/settings.json` allowlists, env vars, hook configurations
- [ ] **Quarterly re-run reminder** — `/schedule` integration so you don't have to remember
- [ ] **Multi-machine sync** — diff your audit results across machines (work laptop vs personal)
- [ ] **Plugin marketplace insights** — flag plugins that have shipped major updates since you installed them
- [ ] **Lighter UI for small audits** — single-page form for installs with <15 items
- [ ] **Time-window selector** — let users pick 30d / 60d / 90d / 180d at runtime

PRs welcome.

---

## 🤝 Contributing

When proposing changes, include:

- A real audit output showing the change in action (paste the markdown export)
- Updated documentation if the workflow changed
- Reproduction recipe if you fixed a bug

The skill is intentionally opinionated about workflow but flexible about content. PRs that:

- Improve agent prompts → likely accepted
- Improve HTML interactions → likely accepted
- Add new safety rails → very likely accepted
- Add additional audit categories → likely accepted
- Restructure the dual-half workflow → discuss in an issue first

---

## 🙋 Common gotchas

These are real things that bit early users (and the skill author):

- **`~/.claude/skills/` vs `~/.claude/plugins/installed/`** — older Claude Code versions used the latter. As of CC 1.x, standalone skills live at `~/.claude/skills/`. The skill verifies paths before deleting, but you may see references to the older path in third-party docs.
- **Restart required after plugin changes** — the manifest is read at session start. Changes to `installed_plugins.json` don't take effect until you fully quit and relaunch Claude Code.
- **Description field in rule frontmatter** — per the official spec, rules don't support `description:` (that's a skills-only field). It's silently ignored. The audit catches this and tells you, but the skill doesn't fix it automatically (cosmetic).
- **CLAUDE.md "on demand" classification** — there's no "on demand" loading mode for rules. It's a mental model people often have, but it maps to "path-scoped" in the actual API. The audit reclassifies these.
- **Agent invocation count = real signal, not perfect signal** — the agents count formal Skill tool calls + slash commands + Bash patterns. Custom invocation paths (e.g. a plugin you trigger via a hook rather than a slash command) may show as "0 invocations" even when actively used. Override the agent if you have private context.

---

## 📜 Credits

Pattern originally developed by [Ronnie Meagher](https://github.com/MJWNA) across two production audits on a Claude Code installation with 25 plugins, 25 standalone skills, and 14 user-scope rules. The dual-half approach (skills then rules) and the parallel-agent + interactive-HTML decision pattern emerged from real cleanup work — not theory.

Detailed philosophy: [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md).

Built with [Claude Code](https://docs.claude.com/en/docs/claude-code) — the skill audits the very tool that built it.

---

## 📜 License

[MIT](LICENSE) — use it, fork it, modify it, ship it. If you make improvements, PRs back to the main repo are appreciated but not required.

---

## 🔗 Related

- [Claude Code Skills documentation](https://docs.claude.com/en/docs/claude-code/skills)
- [Claude Code Memory + Rules documentation](https://docs.claude.com/en/docs/claude-code/memory)
- [skill-creator](https://github.com/anthropics/claude-plugins-official) — the official skill for creating skills (used to scaffold this one)

---

*Audit early, audit often. Or at least, audit once.*
