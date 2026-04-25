---
description: Audit installed plugins and standalone skills using session-history evidence. Builds an interactive HTML decision tool, then cleans up safely with quarantine-based reversibility.
allowed-tools: Bash, Read, Write, Edit, Agent, Glob, Grep
---

Run the skills + plugins half of the config audit.

The user has invoked this slash command, so they want the skills audit specifically — skip the "do you want both halves" prompt and go straight into the skills workflow.

## Locating the skill on disk

Every path below resolves through `$SKILL_DIR`. When this command runs as a plugin, Claude Code sets `CLAUDE_PLUGIN_ROOT` to the plugin's installed directory; for the standalone-skill install (no plugin manifest), the canonical install path is `~/.claude/skills/claude-config-audit/`. Use whichever exists:

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/claude-config-audit}"
[ -f "$SKILL_DIR/SKILL.md" ] || { echo "claude-config-audit not found at $SKILL_DIR" >&2; exit 1; }
```

All references below — to scripts, assets, references — go through `$SKILL_DIR`. Don't write paths that depend on the user's cwd or on a specific marketplace name.

## Workflow

Follow `$SKILL_DIR/SKILL.md` and `$SKILL_DIR/references/skills-audit-workflow.md`. The phases are:

1. Run the prerequisite check + discovery: `bash "$SKILL_DIR/scripts/verify-prerequisites.sh"` and `bash "$SKILL_DIR/scripts/discover-config.sh"`.
2. Run `python3 "$SKILL_DIR/scripts/analyze-session-history.py" --window-days 90 > /tmp/session-counts.json` to produce deterministic invocation counts. Pass this file to each agent so verdicts are grounded in real data, not invented counts.
3. If a previous audit exists in `~/.claude/.audit-history/`, run `python3 "$SKILL_DIR/scripts/audit-history.py" diff skills <items.json>` to surface deltas only — items new since last audit, items where invocation evidence has changed, snoozed items now due.
4. Categorise items into 4-6 buckets and dispatch parallel sub-agents (5 buckets max).
5. **Add a security-pass agent** alongside the bucket agents — it scans hooks, MCP servers, and settings for shell-injection risks, suspicious endpoints, hardcoded tokens, and over-broad `allowed-tools`. See `$SKILL_DIR/references/parallel-agent-patterns.md` for the prompt.
6. Synthesise into a populated audit data JSON file: an object with `sections` (the bucket arrays) and `securityFindings` (from the security-pass agent). Include `verdict`, `confidence`, and `reasonCodes` per item.
7. Inject via `python3 "$SKILL_DIR/scripts/inject-audit-data.py" "$SKILL_DIR/assets/skills-audit-template.html" <data.json> -o "$PWD/skills-audit.html"` — never hand-edit the placeholder.
8. User reviews in browser → generates markdown → pastes back.
9. Confirm the deletion plan with the user.
10. Quarantine deletions (don't `rm -rf`): use `bash "$SKILL_DIR/scripts/quarantine.sh" init`, then `add` plugin cache dirs and standalone skill dirs into the quarantine session. Write the MANIFEST.md with `quarantine.sh manifest`.
11. After successful execution, run `python3 "$SKILL_DIR/scripts/audit-history.py" save skills <markdown-path>` to record the user's decisions for next time.
12. Restart prompt + tell user how to restore from quarantine if anything goes wrong (`bash "$SKILL_DIR/scripts/restore.sh" <session>`).

Per `$SKILL_DIR/references/safety-protocol.md`: never `rm -rf` directly. Always `mv` to quarantine. The quarantine has a 7-day TTL and a one-line restore command.

If `$ARGUMENTS` was provided, treat it as a hint about scope (e.g. "just plugins" → skip the standalone skills bucket).
