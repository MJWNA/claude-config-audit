# Parallel Agent Patterns

How to dispatch and synthesise sub-agents for both audit halves. The success of the skill depends on getting agent prompts right — vague prompts produce vague verdicts.

## Why parallel

A single agent doing 50 items sequentially would:

- Lose precision in long context (recent items get the most attention)
- Take ~10x longer
- Mix categories and confuse overlap analysis (e.g. "which Slack tool does the user actually use?" requires looking at all Slack-related items together)

Independent agents per bucket finish in parallel and each keeps a tight context.

## The dispatch pattern

Always dispatch in a single message with multiple `Agent` tool calls:

```
[message with 4-5 Agent tool calls]
  Agent({ subagent_type: 'compound-engineering:research:session-historian', prompt: '...bucket 1 prompt...' })
  Agent({ subagent_type: 'compound-engineering:research:session-historian', prompt: '...bucket 2 prompt...' })
  Agent({ subagent_type: 'compound-engineering:research:session-historian', prompt: '...bucket 3 prompt...' })
  Agent({ subagent_type: 'compound-engineering:research:session-historian', prompt: '...bucket 4 prompt...' })
  Agent({ subagent_type: 'compound-engineering:research:session-historian', prompt: '...bucket 5 prompt...' })
```

If `compound-engineering:research:session-historian` isn't available, fall back to `general-purpose`. The session-historian is preferred because it knows where Claude Code, Codex, and Cursor session storage live.

## Skills audit prompt template

```
You are auditing usage patterns in <USER>'s Claude Code session history to inform a skills/plugins audit.

CONTEXT:
- The user runs <BUSINESSES / PROJECTS — 1-2 sentences from discovery>
- Main projects: <list from CLAUDE.md or workspace>

Search Claude Code session history (and Codex/Cursor if relevant) for evidence of usage of these <N> <plugins | standalone skills>. Cover the last 90 days.

ITEMS TO AUDIT:
1. **<item-name>** — <one-line description from SKILL.md or plugin.json>. Look for: <specific tool/command names to grep for>.
2. **<item-name>** — ...
[N items total]

CRITICAL: Count REAL invocations only.
- Formal `Skill` tool calls (`"skill":"<name>"` in tool_use blocks)
- User-typed slash commands (`<command-name>/<name></command-name>` user message tags)
- Underlying script Bash calls if applicable

DO NOT count:
- Skill descriptions appearing in `<system-reminder>` skill registries (they appear in every recent session)
- Mentions of the item in user prompts that don't actually trigger it

For EACH item, report:
- **Usage frequency**: Never / Rarely (1-3) / Occasionally (4-10) / Often (10+) / Constant — based on actual session evidence
- **Most recent invocation**: date if found
- **Evidence**: 1-2 concrete quotes/examples from sessions
- **Overlap analysis**: where it competes with another tool, which one the user actually uses
- **Recommendation**: KEEP / DELETE / MAYBE with one-sentence reasoning

Format as structured markdown sections per item. Be honest — if you find no evidence, say so plainly. Don't pad.

Search session storage at typical Claude Code locations: ~/.claude/projects/, ~/Library/Caches/claude-cli-nodejs/. Also check Codex (~/.codex/) and Cursor (~/.cursor/projects/) if they exist.
```

## Rules audit prompt templates

The rules half uses 4 different agent types with distinct prompts. See `rules-audit-workflow.md` for the dispatch sequence; each agent's prompt template:

### Agent 1 — Existing rules audit

```
You are auditing <USER>'s user-scope Claude Code rules at `~/.claude/rules/`.

CONTEXT: <BUSINESSES / PROJECTS>

YOUR TASK:
1. **Inventory** — list every file in `~/.claude/rules/`, with size in lines and bytes.
2. **Frontmatter audit** — for EACH rule, check for YAML frontmatter (between `---` markers), enumerate fields present (paths / description / etc.), flag any that contradict the loading mode declared in the user's CLAUDE.md.
3. **Quality assessment** — 1-line verdict per rule: fresh / stale / has known issues. Flag stale references to deleted skills/projects.
4. **Cross-rule duplication check** — content appearing in 2+ rule files.
5. **CLAUDE.md alignment check** — does the rule index in CLAUDE.md match what's in `~/.claude/rules/`?

OUTPUT FORMAT — structured markdown:
- ## Inventory (table)
- ## Per-rule findings (per rule: frontmatter, quality, issues, recommendation: keep / minor edit / major refresh / delete)
- ## Cross-cutting issues (duplications, mismatches, frontmatter inconsistencies)

Be specific — quote file lines, give exact field names. NO edits — report only.
```

### Agent 2 — Codebase pattern scan

```
You are scanning <USER>'s project workspace to identify GAPS in their user-scope Claude Code rules — patterns that recur across multiple projects and would benefit from being promoted to user-scope.

CONTEXT: <BUSINESSES / PROJECTS>

EXISTING USER-SCOPE RULES (don't propose duplicates): <list rule filenames from discovery>

YOUR TASK — investigate <list of project rule directories from discovery>.

For each project rule directory, read its files. Look for:
- **Cross-project repetition** — content appearing in 2+ projects' rules
- **Implicit conventions** — patterns consistent across projects but not documented as a rule
- **Domain-specific recurring needs** — patterns specific to user's business domain

OUTPUT — for each candidate:
- **Pattern name + found in (file:line refs)**
- **Description**
- **Why promote**: why it should be user-scope
- **Suggested rule name**
- **Loading mode**: always (no frontmatter) / path-scoped (with paths)
- **Estimated content**: 1-2 sentence summary

The bar for promotion is HIGH: must be true across 3+ projects AND not vary per-project AND have non-obvious content.

Also include an **Anti-recommendations** section — patterns that vary too much per-project to be safely promoted.
```

### Agent 3 — Official spec lookup

```
You are researching the OFFICIAL Claude Code specification for user-scope and project-scope rules in `.claude/rules/*.md` files.

USE THESE SOURCES IN ORDER:
1. Context7 MCP if available: mcp__context7__resolve-library-id then query-docs for "claude-code rules frontmatter"
2. WebFetch the official docs: https://code.claude.com/docs/en/memory, https://code.claude.com/docs/en/skills
3. WebSearch for known parser bugs and community workarounds (issue #17204, #23478, #13905)

ANSWER (cite source URL for each):
1. Canonical name: rules / memory / instructions?
2. Is YAML frontmatter required, optional, or unsupported?
3. Supported frontmatter fields (table: name, type, purpose, default, example)
4. Path-scoping field name + format
5. Loading modes (always / path-scoped / on-demand?)
6. Behaviour of files with no frontmatter
7. Description field — does it work for rules?
8. Naming conventions
9. Loading order / priority on conflict
10. User-scope vs project-scope differences

Also: known parser bugs and community workarounds.

If a question can't be answered from official docs, say "NOT IN DOCS" — don't guess.
```

### Agent 4 — Session-history archaeology

```
You are doing a session-history archaeology pass to identify candidates for NEW user-scope rules.

CONTEXT: <BUSINESSES / PROJECTS>

EXISTING USER-SCOPE RULES (don't propose duplicates): <list>

Search the last 90 days of session history at `~/.claude/projects/` for THREE signals:

**Signal A: Repeated corrections** — instances where the user corrected Claude on the same kind of mistake more than once across different sessions
**Signal B: Repeated explanations** — instances where the user re-explained the same context across multiple sessions
**Signal C: Patterns the user endorsed** — when did they say "yes exactly", "perfect", "spot on"?

For EACH candidate rule, report:
- Trigger pattern (with quotes if possible)
- Frequency (N distinct sessions)
- Date range
- Projects affected
- Why a rule would help
- Suggested rule name + loading mode + content sketch

A real candidate must:
1. Appear in 3+ distinct sessions OR have caused a high-cost mistake
2. Not be inferable from existing rules
3. Have stable content (won't change every month)
4. Be more useful at user-scope than project-scope

Be honest about confidence. Insufficient signal = MAYBE not RECOMMEND.
```

## After agents return — synthesis

When all agents complete:

1. Read the result of each (notification arrives via task-notification message — don't tail the output file)
2. Build the populated data array for the HTML
3. For overlap cases (item appears strongly in two buckets), defer to the deeper analysis — don't double-count
4. Cross-reference findings: if Agent 1 (existing rules audit) flags a stale slash-command reference and Agent 4 (session-history) shows that command was deleted recently, surface this as a high-priority refresh candidate
5. Build the HTML and save to user's workspace
6. Hand off to the user

## Don't tail agent output files

When you launch an Agent, you get back an `output_file` path. **Never read it.** The transcript is the agent's tool output — reading it pulls noise into your context, defeating the purpose of forking. The completion notification arrives as a user-role message in a later turn with the agent's final summary. That's all you need.
