---
description: Audit user-scope and (optionally) project-scope rules. Five-section interactive HTML decision tool with full proposed file content for new rule candidates. Edits are quarantined for reversibility.
allowed-tools: Bash, Read, Write, Edit, Agent, Glob, Grep
---

Run the rules half of the config audit.

The user has invoked this slash command, so they want the rules audit specifically — skip the "do you want both halves" prompt.

## Workflow

Follow `claude-config-audit/SKILL.md` and `claude-config-audit/references/rules-audit-workflow.md`. The phases are:

1. Run the prerequisite check + discovery. If `$ARGUMENTS` mentions "project" or `$PWD/.claude/rules/` exists, run discovery with `--project` to pick up project-scope rules.
2. If a previous rules audit exists in `~/.claude/.audit-history/`, run `scripts/audit-history.py diff rules <items.json>` so you can surface only changed items.
3. Read every rule file in full (existing rules need full-content review for the quality assessment).
4. Read the user's `~/.claude/CLAUDE.md` for the rule index.
5. Dispatch 4 parallel sub-agents:
   - Existing-rules audit (frontmatter + quality + duplication + CLAUDE.md alignment)
   - Codebase pattern scan (cross-project repetition → user-scope candidates)
   - Official spec lookup (current rule frontmatter spec + known parser bugs)
   - Session-history archaeology (repeated corrections → new rule candidates)
6. **Add a security-pass agent** that checks the user's existing rules for stale references to deleted skills/plugins, dangerous patterns the rules are inadvertently encouraging, and any rule content that would leak credentials if shared.
7. Synthesise into the five-array data shape: `existingRules`, `mismatches`, `newRules` (with full `proposedContent`), `extensions` (with full `proposedSnippet`), `refreshes`. Add `confidence` per item.
8. Read `assets/rules-audit-template.html`, inject the data, save to user's CWD as `rules-audit.html`.
9. User reviews → generates markdown (which now includes the full proposed content per new rule, not just sketches) → pastes back.
10. Confirm the change plan with the user.
11. Before any edit, snapshot `~/.claude/CLAUDE.md` and `~/.claude/rules/` to a quarantine session (use `scripts/quarantine.sh init` then `add ... --copy`). This means rule edits ARE reversible from quarantine.
12. Execute: write new rule files (parallel), then read+edit existing rules sequentially, then read+edit CLAUDE.md.
13. Run `scripts/audit-history.py save rules <markdown-path>` to record decisions.
14. Restart prompt + smoke-test ideas (one phrase per new rule).

Per `references/safety-protocol.md`: edit existing rules only after they're snapshotted to quarantine. Never edit CLAUDE.md without backing it up first.

If `$ARGUMENTS` was provided and contains "project" or "$PWD", include project-scope coverage; otherwise default to user-scope only.
