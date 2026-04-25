---
name: claude-config-audit
description: Audit and clean up a Claude Code installation — installed plugins, standalone skills under ~/.claude/skills/, and user-scope rules under ~/.claude/rules/. Uses parallel sub-agents to scan the user's actual session history for usage evidence, generates two interactive HTML decision tools (skills audit + rules audit), then executes cleanup safely with backups. **Use this skill whenever the user mentions any of: "audit my Claude config", "audit my skills", "audit my plugins", "audit my rules", "clean up my Claude setup", "which skills should I delete", "spring clean Claude", "skills audit", "rules audit", "what plugins am I actually using", "trim my Claude install", "evaluate my Claude installation", "context bloat in Claude", "Claude config review", "claude code skill audit", "audit-claude-config", or any variation expressing the desire to evaluate, decide on, or clean up their Claude Code configuration.** Don't wait for the user to spell out the workflow — if they signal intent to evaluate or clean up their setup, this is the right skill.
---

# Claude Config Audit

A production-ready, evidence-based audit workflow for Claude Code installations. Helps users decide what to keep, delete, or refresh across three categories: **plugins**, **standalone skills**, and **user-scope rules**.

## What this skill produces

By the end of running this skill the user will have:

1. **Two interactive HTML decision tools** saved to their workspace, with their actual config pre-loaded and parallel-agent verdicts visible per item
2. **A markdown report** they can copy back to chat with their final decisions
3. **A clean Claude Code installation** with their chosen items deleted/edited, backups in place, and the CLAUDE.md rule index restructured to match the official spec

This is not a generic recommendation. The agents read the user's own session history to ground every verdict in evidence — invocation counts, dates, project context, overlap analysis.

## Core idea

Claude Code installations accumulate over time. Plugins get installed for one task and forgotten. Skills get authored in a burst of enthusiasm and never invoked. Rules get written based on a single correction and become stale. **You can't make good keep/delete decisions without evidence.** This skill produces the evidence then lets the user decide.

The workflow is split into two halves that share the same shape:

- **Skills audit** — plugins + standalone skills (the executable layer)
- **Rules audit** — user-scope rules under `~/.claude/rules/` (the instruction layer)

Each half follows: **discover → parallel-agent scan → HTML decision tool → user decisions → safe execution.**

## When to run which half

Most users want both. If the user only wants one:

- **Skills audit only** — when context bloat is the primary concern, when slash command lists feel cluttered, when `/plugin` UI takes too long to load
- **Rules audit only** — when they suspect rule drift, when they've never audited rules before, when CLAUDE.md feels out of date

Run them sequentially in the order above (skills first, rules second). The skills audit may delete plugins whose absence affects the rules audit (e.g. removing a plugin that ships its own rule files).

## Prerequisites checklist

Before starting, verify:

- The user is on Claude Code (not Claude.ai) — this skill needs subagent dispatch and Bash access
- They're in a directory they can write to (the HTML files land there)
- They have at least one of: a populated `~/.claude/plugins/`, `~/.claude/skills/`, or `~/.claude/rules/`
- They understand this will require ~30-60 minutes of their attention (longer for first-time audits)

If they want to do this autonomously without interaction, this skill is the wrong tool — it's interaction-driven by design.

## High-level workflow

```
[SKILLS AUDIT HALF]
  1. Discover installed plugins + standalone skills
  2. Dispatch ~5 parallel session-historian agents to scan usage
  3. Build HTML from template + agent findings, save to user's workspace
  4. User reviews in browser, generates markdown, pastes back to chat
  5. Confirm the deletion plan
  6. Execute: backup manifest, edit installed_plugins.json, rm cache dirs, rm skill dirs
  7. Verify

[RULES AUDIT HALF]
  1. Discover existing rules + read each
  2. Dispatch ~4 parallel agents (existing-rules audit, codebase pattern scan, official spec lookup, session-history archaeology)
  3. Build HTML from template + agent findings + spec citations
  4. User reviews, generates markdown, pastes back
  5. Confirm the change plan
  6. Execute: write new rule files, edit existing rules, restructure CLAUDE.md rule index
  7. Verify and prompt the user to restart Claude Code
```

Each half is a separate, recoverable transaction. The user can stop at any point.

## Execution playbooks (read these as you go)

These are the detailed workflow guides. Read each one when you reach the corresponding phase — don't try to keep all of them in context at once.

| When | Read this |
|---|---|
| Starting the skills audit half | `references/skills-audit-workflow.md` |
| Starting the rules audit half | `references/rules-audit-workflow.md` |
| Before any destructive action | `references/safety-protocol.md` |
| When dispatching parallel agents | `references/parallel-agent-patterns.md` |
| When discussing rule frontmatter / spec | `references/claude-config-spec.md` |

## HTML template usage

Two production-ready HTML templates ship with this skill:

- `assets/skills-audit-template.html` — for the skills+plugins half
- `assets/rules-audit-template.html` — for the rules half

Each is a self-contained single-file app with localStorage persistence, a sticky toolbar, expandable rule cards, decision radio buttons, mismatch filtering, and markdown export. You do NOT write your own HTML — copy these to the user's workspace and inject the audit data.

**Injection points:** Each template has a single placeholder near the top of the script section:

```js
const data = /* AUDIT_DATA_INJECTION_POINT */ [];
```

Replace `[]` with the JavaScript array of audit items built from the parallel-agent findings. The shape of each item is documented at the top of the template file. Keep the rest of the template untouched — the CSS, layout, and interaction logic don't need per-user customisation.

After injecting the data, save the populated HTML to the user's CWD as `skills-audit.html` or `rules-audit.html` and tell them to run:

```bash
open ./skills-audit.html
# or
open ./rules-audit.html
```

(Or `xdg-open` on Linux, `start` on Windows.)

## Output format for the markdown report

The HTML's "Generate Markdown" button produces this format. When the user pastes it back, you'll receive something like:

```markdown
# 🎯 Claude Skills Audit Results
_Generated: 2026-04-25 09:12 AEST_

## 🗑️ Delete
### 📦 Plugins — Core Dev Tooling
- **pyright-lsp** (plugin, 0 in 90d)
- **typescript-lsp** (plugin, 0 in 90d)
...

## ✅ Keep
...

## ⚠️ Where I overrode the agent (3)
- **frontend-design** — agent said MAYBE, I chose KEEP — used recently on AffiliateApp
...
```

Parse the user's decisions from this markdown — don't re-ask for them. Then proceed to the execution phase.

## Safety guarantees

This skill modifies user-scope config that affects every Claude Code session on their machine. Before any destructive action you MUST follow `references/safety-protocol.md`. The non-negotiable parts:

- **Always backup before modifying `installed_plugins.json`**: `cp ~/.claude/plugins/installed_plugins.json{,.bak}`
- **Always show the exact command list before executing destructive operations**, even if the user has approved the plan
- **Verify the path exists before `rm -rf`** — the difference between `~/.claude/skills/` and `~/.claude/plugins/installed/` has caught real users (and authors of this skill)
- **For rule edits, read the file first** so the Edit tool has anchor strings to match against
- **Never skip the manifest edit before deleting cache dirs** — orphaned cache dirs are recoverable (re-install the plugin), orphaned manifest entries cause harder-to-debug load errors
- **After plugin changes, prompt for Claude Code restart** — the manifest is read at session start

## Tone and pacing

This skill takes the user through a multi-stage decision process. They will be tired by the end. Keep responses tight:

- Show the agent verdicts visually (badges, counts) not as long prose
- When summarising findings, lead with the headline number then 3-5 specific examples — never list all 50 items in chat
- When describing destructive actions, use the format "X to delete (manifest + cache + skill dirs)" not "I will now proceed to remove the following thirteen plugins from your Claude Code installation by..."
- Default to bullet lists over paragraphs
- Treat the HTML as the primary UI. Chat is for the bookends — discovery summary at start, execution confirmation at end

## What not to do

- Don't make the user re-explain their setup if you can `ls` their directories
- Don't dispatch agents serially when they're independent — always parallel-dispatch in one message
- Don't write your own HTML — use the templates
- Don't recommend deletion without invocation evidence from the user's own session history
- Don't auto-execute deletions without showing the command list and getting confirmation
- Don't forget to back up `installed_plugins.json` before editing
- Don't generate "general advice" markdown — the report must be grounded in this user's actual config
- Don't skip the prerequisites check, even if it feels obvious
- Don't overwrite an existing `skills-audit.html` or `rules-audit.html` in the user's CWD without warning them — those may contain in-progress decisions

## Common follow-ups

After the audit completes, the user often wants:

- **A `/schedule` cron** to re-run the audit quarterly
- **A `claude-config-doctor` style health check** between audits
- **Migration of project-scope rules to user-scope** (this is a separate workflow — point them to `references/rules-audit-workflow.md` "Promoting rules" section)

If they ask, offer once and move on. Don't pitch follow-ups they didn't signal interest in.

## Compatibility

- Claude Code on macOS, Linux, Windows (WSL recommended). Native Windows works for read paths but `rm -rf` semantics differ.
- Requires Bash and Python 3 (Python is used only by the `discover-config.sh` script for JSON parsing — replaceable with `jq` if available).
- Tested with Claude Code 1.x.
- HTML output works in any modern browser with localStorage. No internet access required to use the HTML.
