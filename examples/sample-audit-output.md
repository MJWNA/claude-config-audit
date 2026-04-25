# Sample Audit Output

What a real run of `claude-config-audit` produces. The exact items will be specific to *your* installation — these placeholders show the **shape** of the output, not anyone's specific config.

## Skills audit half — final state

```
=== Cleanup complete ===

Before  →  After
  N plugins         →  N-X plugins (cut X)
  M skills          →  M-Y skills (cut Y)
  N+M total items   →  cleaner state

X plugins quarantined (manifest edited + cache moved to quarantine):
  <plugin-a>, <plugin-b>, <plugin-c>, ...

Y standalone skills quarantined (mv to quarantine, not rm -rf):
  <skill-a>, <skill-b>, ...

Quarantine session:  ~/.claude/.audit-quarantine/<ISO-timestamp>/
Restore everything:  bash <skill-dir>/scripts/restore.sh <session>
Auto-purge after:    7 days

Restart Claude Code to load the trimmed config.
```

## Headline shape — what evidence looks like

```
Top kept items (high invocation, high confidence):
  <plugin-or-skill-name>   220 calls in 90d   (description summary)
  <plugin-or-skill-name>   115 calls / 49 sessions
  <plugin-or-skill-name>    66 calls in 90d
  ...

Top deleted items (zero invocation, high confidence):
  <plugin-or-skill-name>     0 in 90d   (no triggers found, evidence: nothing in last 90d sessions)
  <plugin-or-skill-name>     0 in 90d   (overlaps with another tool the user invokes 100x more)
  ...

Items deferred to "Maybe":
  <plugin-or-skill-name>     0 in 30d but installed 5 days ago — too new to judge
  <plugin-or-skill-name>     2 in 90d, both via cron — not user-invoked, but cron is the point
  ...
```

## User overrides of the agent

A typical 50-item audit produces 3-7 user overrides. The HTML decision tool tracks them and includes them in the markdown export under "Where I overrode the agent (N)":

```
Kept despite agent recommending DELETE:
  <item>  — "I'm planning to wire this up next month"
  <item>  — "I do use this in <other terminal>, agent only sees CC sessions"

Deleted despite agent recommending MAYBE:
  <item>  — "Honestly I won't reach for it. Better to delete than carry."
```

These overrides are valuable signal:
- For *this* audit: they get applied without re-asking
- For the *next* audit (via decision memory): the previous decision + reason is shown next to the item, so you don't have to re-justify the same choice

## Rules audit half — final state

```
Before  →  After
  N rules          →  N+K rules (added K, edited L, refreshed M)
  CLAUDE.md rule index: P misclassifications fixed

K new rules added (sources: session-history archaeology + cross-project pattern scan):
  <rule-name>.md  (always-loaded)   — N sessions of repeated correction
  <rule-name>.md  (path-scoped)     — M projects share the same convention
  ...

L existing rules extended:
  <rule-name>.md  (+ small section on Y, + worked example for Z)
  ...

CLAUDE.md rule index restructured into:
  - Always-loaded sub-table (workflow + identity + integration baselines)
  - Path-scoped sub-table  (loads only when matching files are open)
```

## Time invested

```
Discovery + agent dispatch:  ~5 minutes (parallel — wait time, not work time)
Skills audit review:         ~25 minutes (50 items, 30s each)
Rules audit review:          ~30 minutes (mix of existing + new candidates + extensions)
Cleanup execution:            ~5 minutes (mostly the user reading the deletion plan)
Total:                       ~60-65 minutes for a first-time audit

Subsequent audits using decision memory:  ~10-15 minutes (only deltas surfaced)
```

## What the agents typically get right

- Plugin-vs-CLI overlaps (e.g. an MCP plugin shows zero invocations while the equivalent CLI is invoked hundreds of times — clean delete)
- Plugins that ship MCP servers but whose authenticate/auth flow gets called more than the actual tools (pure context cost)
- High-volume items where the evidence is overwhelming (one tool dominating its category)
- Stale references in rules (rule mentions a slash command that was renamed or deleted)

## What the agents typically miss

- Items installed in the last 30 days — not enough session signal yet, the agents bias toward "looks underused"
- Custom invocation paths — items triggered by hooks or non-standard tool calls rather than the formal `Skill` tool / slash commands
- User intent ("I'm about to wire this up") — agents only see history, not future plans

The HTML decision tool's "Maybe" + override pattern is designed for exactly these cases. The user's keep-with-reason becomes input to the next audit's decision memory.

## What changes between v1 and v2

| Behaviour | v1 | v2 |
|---|---|---|
| Deletion | `rm -rf` | `mv` to timestamped quarantine, 7-day TTL |
| Backup | `installed_plugins.json` only | All edited files (manifest, rules, CLAUDE.md, settings) |
| Reversibility | Manifest only | Everything in the quarantine session |
| Confidence per item | Implied by verdict | Explicit `confidence: high/medium/low` + `reasonCodes[]` |
| Cross-run memory | None | `~/.claude/.audit-history/` + delta-only re-runs |
| Security review | Bundled into bucket agents | Dedicated security-pass agent |
| Project-scope | Read-only side-channel | First-class with `--project` flag |
| Slash commands | Description-triggered only | `/audit-skills` and `/audit-rules` |
