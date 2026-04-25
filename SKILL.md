---
name: claude-config-audit
description: Audits and cleans up a Claude Code installation — installed plugins, standalone skills, user-scope rules, hooks, MCP servers, and project-scope config. Scans the user's actual session history for usage evidence, builds interactive HTML decision tools with confidence-tiered recommendations, then executes cleanup safely with quarantine-based reversibility and decision memory across runs. Use whenever the user wants to audit, prune, clean up, evaluate, trim, spring-clean, doctor, or review their Claude Code config; whenever ~/.claude/ feels bloated, slow, or context-heavy; whenever they want to know which skills, plugins, hooks, or rules they actually use; or whenever they want a fresh-config feeling without losing what's working. Don't wait for the user to spell out the workflow — if they signal intent to evaluate or clean up their setup, this is the right skill.
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
[SKILLS AUDIT HALF — also reachable via /audit-skills]
  1. Run prerequisite check + discovery (covers user-scope and project-scope)
  2. Read decision history (scripts/audit-history.py latest skills) — surface only deltas if a previous audit exists
  3. Dispatch parallel agents: 4-5 bucket agents + 1 security-pass agent (for hooks, MCPs, settings)
  4. Synthesise findings — each item gets verdict + confidence + reasonCodes
  5. Build skills-audit.html from the template, save to user's workspace
  6. User reviews in browser, generates markdown (with embedded decisions envelope), pastes back to chat
  7. Confirm the deletion plan
  8. Execute via quarantine: backup manifest, edit installed_plugins.json, MOVE cache dirs and skill dirs into quarantine session (not rm -rf)
  9. scripts/audit-history.py save skills <markdown-path>
  10. Verify + restart prompt + show how to restore from quarantine

[RULES AUDIT HALF — also reachable via /audit-rules]
  1. Discover existing rules + read each (user-scope; --project for project-scope)
  2. Read decision history for rules
  3. Dispatch 5 parallel agents: existing-rules audit, codebase pattern scan, official spec lookup, session-history archaeology, security pass
  4. Synthesise into 5 sections (existing, mismatches, new candidates with full proposedContent, extensions, refreshes) — each item gets confidence
  5. Build rules-audit.html, save to user's workspace
  6. User reviews, generates markdown (now self-contained — includes proposedContent), pastes back
  7. Confirm the change plan
  8. Snapshot CLAUDE.md and rules/ to quarantine first, then write new rules, edit existing, restructure CLAUDE.md
  9. scripts/audit-history.py save rules <markdown-path>
  10. Verify + restart prompt + smoke-test ideas + quarantine restore instructions
```

Each half is a separate, recoverable transaction. The user can stop at any point. Quarantine means even completed audits are reversible for 7 days.

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

**Injection mechanism:** Each template contains a JSON-shaped placeholder near the top of the script section. **Always splice via `scripts/inject-audit-data.py` — never by hand.** Agent output may legitimately contain `</script>` strings or U+2028/U+2029 line-separator characters that break a `<script>` tag if injected raw; the script JSON-stringifies the data and escapes those four sequences.

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/claude-config-audit}"
DATA_PATH="$(mktemp /tmp/audit-data.XXXXXX).json"
# Write the populated audit data as JSON to $DATA_PATH using the shape
# documented in the corresponding template file.

python3 "$SKILL_DIR/scripts/inject-audit-data.py" \
  "$SKILL_DIR/assets/skills-audit-template.html" \
  "$DATA_PATH" \
  -o "$PWD/skills-audit.html"
```

The shape of each item is documented at the top of the template file. The rest of the template (CSS, layout, render code) does not need per-user customisation.

After injecting, tell the user to run:

```bash
open ./skills-audit.html
# or
open ./rules-audit.html
```

(Or `xdg-open` on Linux, `start` on Windows.)

## Output format for the markdown report

The HTML's "Generate Markdown" button produces a structured markdown document that ends with a machine-readable JSON envelope inside an HTML comment:

```markdown
# 🎯 Claude Skills Audit Results
_Generated: <ISO-timestamp>_

## 🗑️ Delete
### 📦 Plugins — <bucket name>
- **<item-name>** (plugin, <invocation-summary>)
- **<item-name>** (plugin, <invocation-summary>)

## ✅ Keep
- **<item-name>** ...

## ⚠️ Where I overrode the agent (N)
- **<item-name>** — agent said MAYBE, I chose KEEP — <user's reason>

---
<!-- claude-config-audit:decisions
{ "auditType": "skills", "generatedAt": "...", "decisions": {...} }
-->
```

Parse the user's decisions from the markdown sections (don't re-ask). The JSON envelope at the end is for `scripts/audit-history.py save` — call it after execution so the next audit can surface only what's changed.

## Safety guarantees

This skill modifies user-scope config that affects every Claude Code session on the user's machine. Before any destructive action you MUST follow `references/safety-protocol.md`. The non-negotiable parts:

- **Quarantine, don't delete.** Before any `rm -rf`, use `scripts/quarantine.sh init` to create a quarantine session, then `add` to `mv` directories into it. The quarantine has a 7-day TTL. For `mv`'d items (deleted plugins/skills) restore is a single `restore.sh` call. For `--copy`-snapshotted items (CLAUDE.md and rule files about to be edited) the original stays in place; `restore.sh` will surface a CONFLICT prompt so you can choose whether to keep the edit or roll back. Both flows are reversible — neither pretends the latter is one command.
- **Snapshot before editing.** Before any edit to `~/.claude/CLAUDE.md` or `~/.claude/rules/*.md`, copy the file into the same quarantine session (using `quarantine.sh add ... --copy`). Rule edits are otherwise irreversible without the user's own version control.
- **Always show the exact command list before executing**, even if the user has approved the plan in the markdown. The cost of one extra round-trip is small; the cost of an unwanted change is large.
- **Verify the path exists before any `mv` or `rm`**. `rm -rf` and `mv` against non-existent paths can silently succeed, masking the fact that the actual target wasn't touched.
- **For file edits, read the file first** so the Edit tool's anchor matching is reliable.
- **Edit `installed_plugins.json` before removing cache dirs.** Orphaned cache dirs are recoverable (re-install). Orphaned manifest entries cause confusing load errors at session start.
- **After plugin changes, prompt for a Claude Code restart** — the manifest is read at session start.
- **After execution, save the decisions** with `scripts/audit-history.py save <type> <markdown-path>` so the next audit can surface only deltas.

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

After the audit completes, the user often wants one of:

- **A scheduled quarterly re-run** — offer once if there's a `/schedule`-style mechanism available, then move on.
- **A health-check between audits** — light-touch ping that flags new zero-invocation items without the full agent dispatch.
- **Migration of project-scope rules to user-scope** — separate workflow, see `references/rules-audit-workflow.md` "Promoting rules" section.
- **Restore from quarantine** — if they had second thoughts on a deletion. `bash <skill-dir>/scripts/restore.sh <session-dir>` reverses everything cleanly.

Offer once, don't pitch follow-ups they didn't signal interest in.

## Neighbour-skill awareness

Many users will have other skills installed that overlap with parts of this audit's surface area — CLAUDE.md improvers, hook generators, permission optimisers, security scanners. Discover them at runtime by reading the user's installed plugin list (`~/.claude/plugins/installed_plugins.json`) and standalone skills directory (`~/.claude/skills/`), then comparing each one's description against the audit's findings.

If you find an installed skill whose description overlaps with a specific finding in the audit (e.g. "improves CLAUDE.md", "manages permissions", "audits security"), surface it to the user as: *"You already have `<skill-name>` installed — it's better suited for this specific bit. Want to hand off to it?"* The decision is theirs.

**Critical:** never hardcode neighbour-skill names. Every user's setup is different. Discover at runtime; suggest based on description matching; never assume a specific skill exists.

## Compatibility

- Claude Code on macOS, Linux, and WSL. Native Windows works for read-only inspection but the destructive paths (`mv`, `rm -rf`) need a POSIX shell.
- Bash 4+ and Python 3.8+ are required. Python is used for atomic JSON manipulation of `installed_plugins.json` and for the audit-history script.
- HTML output works in any modern browser with localStorage. No internet access required.
- All discovery scripts use portable `stat` fallbacks (BSD `-f` and GNU `-c` both supported).
