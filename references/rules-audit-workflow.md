# Rules Audit Workflow

The detailed playbook for the rules half. Read this when you reach the rules audit phase.

The rules half is structurally different from the skills half — it has 5 distinct decision categories instead of 3, and it produces both edits to existing files AND new file creates.

## What the user ends up deciding

| Category | Action | Decision options |
|---|---|---|
| Existing rule files | Touch the file's content | keep / edit / refresh |
| CLAUDE.md rule index entries | Fix index classification (e.g. "always" → "path-scoped") | edit / skip |
| New rule candidates | Create a new file in `~/.claude/rules/` | add / maybe / skip |
| Extensions to existing rules | Append a section to an existing file | add / skip |
| Spec compliance | Frontmatter modernisation | always required (zero touch needed if user confirms) |

## Phase 1 — Discovery

Run discovery + read every rule file in full:

```bash
bash <skill-dir>/scripts/discover-config.sh
ls ~/.claude/rules/
```

Then read each file completely (not just headers — agents need the full content to assess quality):

```
for f in ~/.claude/rules/*.md; do
  Read $f
done
```

Also read the user's `~/.claude/CLAUDE.md` to get the current rule index.

If the user has project-scope rules, list them too (recurse `<project>/.claude/rules/` for each project they're working on). The codebase-pattern-scan agent needs these.

## Phase 2 — Dispatch 4 parallel agents

This half uses 4 distinctly-purposed agents (NOT 4 of the same kind). See `parallel-agent-patterns.md` for prompt templates.

```
Dispatch in one message:
  Agent 1 (existing rules audit) → compound-engineering:research:repo-research-analyst
  Agent 2 (codebase pattern scan) → compound-engineering:research:repo-research-analyst
  Agent 3 (official spec lookup) → compound-engineering:research:framework-docs-researcher
  Agent 4 (session-history archaeology) → compound-engineering:research:session-historian
```

Each agent has a distinct deliverable:

- **Agent 1** returns: per-rule frontmatter audit + quality assessment + classification mismatch list
- **Agent 2** returns: candidate new rules from cross-project pattern repetition (high bar: 3+ projects)
- **Agent 3** returns: the official Claude Code spec for rule frontmatter, plus known parser bugs and community workarounds
- **Agent 4** returns: candidate new rules from session-history patterns (repeated corrections / explanations / endorsements)

If a session-historian or framework-docs-researcher subagent_type isn't available, fall back to `general-purpose` with the prompt verbatim.

## Phase 3 — Synthesise

When agents complete, build the audit data array with five sections:

```js
const data = {
  existingRules: [...],   // 14ish items, one per existing rule file
  mismatches: [...],      // 5ish items, one per CLAUDE.md classification fix
  newRules: [...],        // 7ish items, candidates from agents 2 + 4
  extensions: [...],      // 3-6 items, small additions to existing rules
};
```

For new rule candidates, **build the full proposed file content** — don't just sketch it. The user will see the actual markdown that would land in their `~/.claude/rules/<name>.md`.

For extensions, build the exact snippet to insert plus the location in the target rule.

For spec compliance, agent 3's findings inform the warnings on each existing rule (e.g. flag any rule with a `description:` field as "loader silently ignores this — see ref").

See `assets/rules-audit-template.html` for the full data shape.

## Phase 4 — Build HTML

Read the rules-audit-template.html, replace the data injection point, write to user's CWD as `rules-audit.html`. Tell them to open it.

The HTML has 5 sections — make sure all 5 are populated even if some are short:

1. Official spec primer (collapsed by default — content from Agent 3)
2. Existing rules audit
3. CLAUDE.md classification mismatches
4. New rule candidates
5. Extensions to existing rules

## Phase 5 — Receive decisions

The user's markdown report will have these sections:

```markdown
## ✅ Existing rules — keep as-is
## ✏️ Existing rules — edit/refresh
## ⚖️ CLAUDE.md classification fixes
## ✨ New rules to add
## 🪡 Extensions to existing rules
## 🤔 Maybe / undecided
```

Parse them. For each new rule under "New rules to add", you have the proposed file content from your earlier synthesis — use it directly.

## Phase 6 — Confirm the change plan

Summarise:

```
📐 Rules audit plan:

📝 X CLAUDE.md classification fixes
✏️ Y existing rules to edit
✨ Z new rule files to create
🪡 W extensions to add to existing rules

Reply 'go' to execute.
```

Wait for confirmation.

## Phase 7 — Execute

Order matters. Do this sequence:

```
1. Write all new rule files (parallel — they're independent)
2. Read each existing rule that needs editing (sequential, one per file)
3. Edit each existing rule with extensions or refresh content
4. Read CLAUDE.md
5. Edit CLAUDE.md to fix classifications + add new rule index entries
```

For the CLAUDE.md edit, prefer **rewriting the rule index table** over piecemeal edits. The new index typically has different structure (split into "Always-loaded" vs "Path-scoped" sub-tables instead of a single mixed table) so a single big edit is cleaner.

## Phase 8 — Verify

```bash
ls ~/.claude/rules/
wc -l ~/.claude/rules/*.md
```

Show the user the final inventory + line counts so they can confirm the new rules landed.

Also re-read CLAUDE.md and confirm the rule index reflects reality.

## Phase 9 — Restart prompt + smoke test ideas

```
🔄 Restart Claude Code to load the new rules.

Smoke tests to try in your next session (one per new rule):
- <rule-1-name>: <a phrase that should trigger it>
- <rule-2-name>: <a phrase that should trigger it>
- ...
```

The smoke tests are valuable — they convert abstract "I added rules" into observable "I see these rules firing on my work."

## Promoting project rules to user-scope

If the user wants to migrate project-scope rules to user-scope (the codebase-pattern-scan agent often surfaces these), the process is:

1. Read the duplicated content from each project's rule file
2. Build a unified user-scope rule that merges them
3. Add it as a new rule (Phase 7 above)
4. **Don't delete the project-scope rules automatically** — those may have project-specific overrides the user wants to preserve. Flag them for the user to review later.

## Common pitfalls

- **Description field gets re-added** — Some Claude versions auto-suggest `description:` in frontmatter. Per the official spec, it's silently ignored for rules. If a user's existing rules have it, leave it alone (cosmetic). If creating a new rule, omit it — the rule will load via the same mechanism (no frontmatter = always-load) without the decorative field.
- **CLAUDE.md "on demand" classification** — There's no "on demand" loading mode for rules per the official spec. It's a mental model the user has, but it maps to "path-scoped" in reality. The audit fixes this.
- **YAML-list `paths:` parser bugs** — issue #17204. The documented form has known issues. Community workarounds: unquoted scalar (`paths: **/*.ts`), or the undocumented `globs:` field. For new rules generated by this skill, use the documented form (it works for most cases) but mention the workarounds in `claude-config-spec.md` if the user wants reliable loading.

## What success looks like

A real first-time rules audit on a 14-rule installation typically produces:

- 0 deletions (rules tend to be small and useful — the deletion test is harsh)
- 5-8 minor edits (CLAUDE.md classification fixes mostly)
- 1-3 high-value refreshes (rules that grew stale or are too short)
- 5-10 new rule candidates from agents 2 + 4 (user accepts ~70% of them)
- 3-6 extensions to existing rules (folding cross-project patterns)

If your audit produces zero new candidates from agents 2 + 4, the user either has very mature rules already or your agent prompts didn't have enough signal — re-check session history depth.
