---
description: Audit installed plugins and standalone skills using session-history evidence. Builds an interactive HTML decision tool, then cleans up safely with quarantine-based reversibility.
allowed-tools: Bash, Read, Write, Edit, Agent, Glob, Grep
---

Run the skills + plugins half of the config audit.

The user has invoked this slash command, so they want the skills audit specifically — skip the "do you want both halves" prompt and go straight into the skills workflow.

## Workflow

Follow `claude-config-audit/SKILL.md` and `claude-config-audit/references/skills-audit-workflow.md`. The phases are:

1. Run the prerequisite check + discovery (`scripts/verify-prerequisites.sh`, `scripts/discover-config.sh`).
2. If a previous audit exists in `~/.claude/.audit-history/`, run `scripts/audit-history.py diff skills <items.json>` to surface deltas only — items new since last audit, items where invocation evidence has changed, snoozed items now due.
3. Categorise items into 4-6 buckets and dispatch parallel sub-agents (5 buckets max).
4. **Add a security-pass agent** alongside the bucket agents — it scans hooks, MCP servers, and settings for shell-injection risks, suspicious endpoints, hardcoded tokens, and over-broad `allowed-tools`. See `references/parallel-agent-patterns.md` for the prompt.
5. Synthesise into the audit data array with `verdict`, `confidence`, and `reasonCodes` per item.
6. Read `assets/skills-audit-template.html`, inject the data, save to user's CWD as `skills-audit.html`.
7. User reviews in browser → generates markdown → pastes back.
8. Confirm the deletion plan with the user.
9. Quarantine deletions (don't `rm -rf`): use `scripts/quarantine.sh` to back up `installed_plugins.json`, then `mv` plugin cache dirs and standalone skill dirs into the quarantine session. Write the MANIFEST.md.
10. After successful execution, run `scripts/audit-history.py save skills <markdown-path>` to record the user's decisions for next time.
11. Restart prompt + tell user how to restore from quarantine if anything goes wrong.

Per `references/safety-protocol.md`: never `rm -rf` directly. Always `mv` to quarantine. The quarantine has a 7-day TTL and a one-line restore command.

If `$ARGUMENTS` was provided, treat it as a hint about scope (e.g. "just plugins" → skip the standalone skills bucket).
