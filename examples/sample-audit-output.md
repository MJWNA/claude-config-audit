# Sample Audit Output

What a real run of `claude-config-audit` produces. From the actual first-time audit of a Claude Code installation with 25 plugins, 25 standalone skills, and 14 user-scope rules.

This is what the user sees in their terminal at the end of a successful run.

## Skills audit half — final state

```
=== Cleanup complete ===

Before  →  After
  25 plugins  →  12 plugins (cut 13)
  25 standalone skills  →  20 standalone skills (cut 5)
  50 total items  →  32 total items

13 plugins removed from manifest + cache:
  pyright-lsp, typescript-lsp, github MCP, commit-commands,
  pr-review-toolkit, claude-md-management, claude-code-setup,
  figma, playground, sentry, Notion, cli-anything, qodo-skills

5 standalone skills removed:
  find-docs, paper-to-pdf, excalidraw-diagram,
  design-studio, update-reference-library

Backup kept at: ~/.claude/plugins/installed_plugins.json.bak

Restart Claude Code to load the trimmed config.
```

## Headline findings from the agent scans

```
Top 5 most-invoked items (kept):
  context7         220 calls in 90d  (library docs lookup)
  superpowers      115 calls / 49 sessions  (planning + brainstorming)
  slack             66 calls in 90d  (mandatory per slack-messaging.md)
  session-complete  36 calls in 90d  (session handoffs)
  ticket-investigator  35 calls / 31 sessions  (workhorse of MTA ticket system)

Top 5 zero-invocation items (deleted):
  pyright-lsp       0 in 90d  (Python work uses ruff/build output instead)
  typescript-lsp    0 in 90d  (TS work uses tsc/Vercel build instead)
  figma             0 in 90d  (5 skills + MCP server, all dormant — pure context bloat)
  github MCP        0 in 90d  (vs gh CLI: 325 calls — CLI wins decisively)
  /review-pr        0 in 90d  (vs /ce-review: 6 calls — compound-engineering wins)
```

## User overrides of the agent

```
The user kept these despite the agent recommending DELETE:
  hookify         — "I want to set this up properly soon"
  warp            — "I do use Warp for most coding sessions"
  ticket-watchdog — "I'll set up a /schedule cron"
  mta-rag         — "Useful for Q&A even if rarely invoked"
  monthly-report  — "Need to schedule for monthly run"

The user deleted these despite the agent recommending MAYBE:
  excalidraw-diagram — "I haven't used it in 4 weeks, won't reach for it"
```

## Rules audit half — final state

```
Before  →  After
  14 rules  →  21 rules (added 7 new)
  CLAUDE.md rule index: 5 misclassifications fixed

7 new rules added:
  parallel-research-default.md  (always)  — 17 sessions of "use Context7 + parallel agents"
  handoff-prompt-portable.md    (always)  — 7 sessions of "give me a handoff prompt"
  humanise-outbound-copy.md     (always)  — 4 sessions of "no em-dashes, no AI tone"
  gemini-model-pinning.md       (path-scoped) — 5 sessions of model name corrections
  vet-construction-domain.md    (always)  — Australian VET + construction reference
  ghl-integration.md            (always)  — GHL webhook 200 + tenant boundary rules
  mta-pt-identity.md            (always)  — MTA never described as "membership"

3 existing rules extended:
  claude-md-standards.md  (+ ARCHITECTURE.md protocol, + frontmatter best-practice)
  stack-defaults.md       (+ server-only guard, + money handling, + cron UTC table)
  vercel-neon-cli.md      (+ --scope mandate, + syd1 region rationale)

CLAUDE.md rule index restructured into:
  - Always-loaded sub-table (workflow + identity + integration baselines)
  - Path-scoped sub-table (loads only when matching files are open)
```

## Time invested

```
Discovery + agent dispatch:  ~5 minutes
Skills audit review:         ~25 minutes (50 items)
Rules audit review:          ~30 minutes (14 existing + 7 new + 6 extensions + 5 mismatches)
Cleanup execution:           ~5 minutes
Total:                       ~65 minutes
```

## What the user said afterwards

> "The dual-half pattern was the right call. The skills audit took the hardest part of decision-making (which 18 of 50 to delete) off my plate by giving me evidence per item. The rules audit was a different kind of work — quality assessment more than usage assessment — but the same UI pattern handled it well."

> "The 'Apply all agent verdicts' button is the killer feature. I went through and overrode 5 of 50 — 10% override rate. Without that button I'd have spent an hour clicking radio buttons before getting to the part where I actually had to think."

> "The 'Where I overrode the agent' section in the markdown output is also subtle but valuable — it's a record of where MY context differs from the agent's, which is itself an artefact worth keeping."

## What the agents got right

- Spotted the github MCP vs gh CLI overlap (zero github MCP calls, 325 gh CLI calls — clean delete)
- Identified the figma plugin's authenticate noise on every session (0 real calls but 334 tool registry mentions)
- Counted 220 context7 query-docs calls — single best evidence in the entire audit
- Caught that superpowers' "using-superpowers" forced-discipline skill was invoked 0 times in 90 days despite being designed to fire every conversation

## What the agents missed

- Couldn't predict the user's intent to set up `/schedule` crons for ticket-watchdog and monthly-report — the user's keep override was the right call here
- Counted Skill tool calls but missed some custom-skill invocations that happen via Bash patterns rather than the Skill tool
- The session-history depth was 90 days — items installed in the last 30 days got a "looks underused" verdict that wasn't fair (small-sample bias)

## What this implies for next-time

- Items installed in the last 30 days probably need a "newly installed — defer audit" tag
- The Bash-pattern-detection for custom skills could be extended (currently focused on formal Skill tool calls)
- A "schedule before deciding" UI option for items the user wants to keep but hasn't actually scheduled would close the loop on watchdog/monthly-report style cases
