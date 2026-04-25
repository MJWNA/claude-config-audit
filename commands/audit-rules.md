---
description: Audit user-scope and (optionally) project-scope rules. Five-section interactive HTML decision tool with full proposed file content for new rule candidates. Edits are quarantined for reversibility.
allowed-tools: Bash, Read, Write, Edit, Agent, Glob, Grep
---

Run the rules half of the config audit.

The user has invoked this slash command, so they want the rules audit specifically — skip the "do you want both halves" prompt.

## Locating the skill on disk

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/claude-config-audit}"
[ -f "$SKILL_DIR/SKILL.md" ] || { echo "claude-config-audit not found at $SKILL_DIR" >&2; exit 1; }
```

`CLAUDE_PLUGIN_ROOT` is set by Claude Code when the command runs as a plugin; the fallback covers the standalone-skill install. Every path below resolves through `$SKILL_DIR` — never write paths that depend on the user's cwd or on a specific marketplace name.

## Workflow

Follow `$SKILL_DIR/SKILL.md` and `$SKILL_DIR/references/rules-audit-workflow.md`. The phases are:

1. Run the prerequisite check + discovery: `bash "$SKILL_DIR/scripts/discover-config.sh"`. If `$ARGUMENTS` mentions "project" or `$PWD/.claude/rules/` exists, run discovery with `--project` to pick up project-scope rules.
2. If a previous rules audit exists in `~/.claude/.audit-history/`, run `python3 "$SKILL_DIR/scripts/audit-history.py" diff rules <items.json>` so you can surface only changed items.
3. Read every rule file in full (existing rules need full-content review for the quality assessment).
4. Read the user's `~/.claude/CLAUDE.md` for the rule index.
5. Dispatch 4 parallel sub-agents:
   - Existing-rules audit (frontmatter + quality + duplication + CLAUDE.md alignment)
   - Codebase pattern scan (cross-project repetition → user-scope candidates)
   - Official spec lookup (current rule frontmatter spec + known parser bugs)
   - Session-history archaeology (repeated corrections → new rule candidates)
6. **Add a security-pass agent** that checks the user's existing rules for stale references to deleted skills/plugins, dangerous patterns the rules are inadvertently encouraging, and any rule content that would leak credentials if shared.
7. Synthesise into a populated audit data JSON object with keys: `existingRules`, `mismatches`, `newRules` (with full `proposedContent`), `extensions` (with full `proposedSnippet`), `refreshes`, and `securityFindings`. Add `confidence` per item.
8. Inject via `python3 "$SKILL_DIR/scripts/inject-audit-data.py" "$SKILL_DIR/assets/rules-audit-template.html" <data.json> -o "$PWD/rules-audit.html"` — never hand-edit the placeholder.
9. User reviews → generates markdown (which now includes the full proposed content per new rule, not just sketches) → pastes back.
10. Confirm the change plan with the user.
11. Before any edit, snapshot `~/.claude/CLAUDE.md` and `~/.claude/rules/` to a quarantine session (`bash "$SKILL_DIR/scripts/quarantine.sh" init` then `add ... --copy`). This means rule edits ARE reversible from quarantine.
12. Execute: write new rule files (parallel), then read+edit existing rules sequentially, then read+edit CLAUDE.md.
13. Run `python3 "$SKILL_DIR/scripts/audit-history.py" save rules <markdown-path>` to record decisions.
14. Restart prompt + smoke-test ideas (one phrase per new rule).

Per `$SKILL_DIR/references/safety-protocol.md`: edit existing rules only after they're snapshotted to quarantine. Never edit CLAUDE.md without backing it up first.

If `$ARGUMENTS` was provided and contains "project" or "$PWD", include project-scope coverage; otherwise default to user-scope only.
