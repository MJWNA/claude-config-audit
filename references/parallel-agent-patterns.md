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
[message with 4-5 Agent tool calls — all in the SAME message so they run in parallel]
  Agent({ subagent_type: '<best-available>', prompt: '...bucket 1 prompt...' })
  Agent({ subagent_type: '<best-available>', prompt: '...bucket 2 prompt...' })
  Agent({ subagent_type: '<best-available>', prompt: '...bucket 3 prompt...' })
  Agent({ subagent_type: '<best-available>', prompt: '...bucket 4 prompt...' })
  Agent({ subagent_type: '<best-available>', prompt: '...security-pass prompt...' })
```

### Picking `subagent_type`

The default is `general-purpose` (always available). If the user has a research-oriented plugin installed that exposes a session-historian or research-analyst subagent, prefer that — it may know where Claude Code / Codex / Cursor session storage lives without prompting.

Discover what's available by checking the Agent tool's enum at runtime, NOT by hardcoding plugin-specific subagent names. The skill must work for any installer.

## Skills audit prompt template

Before dispatching the agents, run the deterministic counter once and pass the JSON to every bucket agent:

```bash
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/claude-config-audit}"
python3 "$SKILL_DIR/scripts/analyze-session-history.py" --window-days 90 \
  > /tmp/session-counts.json
```

The script counts: tool_use blocks where `name=="Skill"` and `input.skill==<name>`, user messages containing `<command-name>/<name></command-name>` tags, and (optionally, via `--bash-pattern`) Bash invocations matching configurable regex patterns. It deliberately ignores skill registry mentions in system reminders and any string that isn't a real invocation. Agents interpret these counts; they do not invent them.

```
You are auditing usage patterns in <USER>'s Claude Code session history to inform a skills/plugins audit.

CONTEXT:
- The user runs <BUSINESSES / PROJECTS — 1-2 sentences from discovery>
- Main projects: <list from CLAUDE.md or workspace>

DETERMINISTIC INVOCATION COUNTS:
Read `/tmp/session-counts.json`. The shape is:
  { "skills": { "<name>": { "count": N, "lastSeen": "...", "byDay": {...} } },
    "slashCommands": { ... }, "bashPatterns": { ... } }
These counts were produced by `scripts/analyze-session-history.py` over the
last 90 days of session JSONL. They are authoritative — do not re-grep the
JSONL to "verify"; do not produce a count that disagrees with the JSON.

ITEMS TO AUDIT:
1. **<item-name>** — <one-line description from SKILL.md or plugin.json>. Look up its count in: skills["<name>"], slashCommands["<command>"], bashPatterns["<label>"].
2. **<item-name>** — ...
[N items total]

YOUR JOB: interpret the counts, don't invent them.
- Use `count` and `lastSeen` from the JSON, verbatim.
- If an item has zero count, say so plainly — don't pad with "you may use it sometimes".
- Look at `byDay` to spot patterns (used heavily then dropped, or used recently after a long gap, etc).
- For overlap analysis (where two tools do similar work), compare their counts and tell the user which one they actually use.

For EACH item, report:
- **Usage frequency**: Never / Rarely (1-3) / Occasionally (4-10) / Often (10+) / Constant — based on the JSON count, not your impression
- **Most recent invocation**: from `lastSeen` (if present)
- **Pattern over time**: 1 sentence on `byDay` (e.g. "ramped through April, none since 04-10")
- **Overlap analysis**: where it competes with another tool, which one the user actually uses (compare counts)
- **Recommendation**: KEEP / DELETE / MAYBE with one-sentence reasoning grounded in the count

Format as structured markdown sections per item. Be honest — if you find no evidence, say so plainly. Don't pad.

DO NOT:
- Re-run `grep` against `~/.claude/projects/*.jsonl` to "double-check" the counts. If the JSON is wrong, that's a bug for the analyzer to fix, not for you to paper over.
- Count skill registry mentions or system-reminder appearances. The analyzer already filters those.
- Invent counts the JSON doesn't contain. If a skill isn't in the JSON, its count is zero.
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
1. If a docs-lookup MCP is available (Context7, framework-docs-researcher, or similar), use it first — it has fresher and more concentrated docs than open web search. Discover at runtime; don't hardcode.
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

## Security-pass agent — run alongside the bucket agents on BOTH halves

A 5th agent for the skills half (or 5th alongside the 4 specialised rules agents) that scans for *safety* concerns the bucket agents won't catch. The agent recommends only — destructive action still requires the user's confirmation.

```
You are doing a security pass over the user's Claude Code config at ~/.claude/.
This is NOT a usefulness audit — that's the other agents. Your job is safety.

CHECK FOR:

1. **Hooks calling network commands** — grep ~/.claude/settings.json and
   ~/.claude/settings.local.json for `hooks.*.command` containing `curl`,
   `wget`, `nc`, `ssh`, or any URL-shaped string. PreToolUse and
   UserPromptSubmit hooks calling external services are particularly risky
   — they fire on every tool call / user message.

2. **Shell-injection patterns in hook commands** — unquoted `$ARG` /
   `${ARG}` usage, `eval`, `bash -c "$ARG"`, `sh -c $ARG`, anything that
   feeds user-controlled data into a shell context.

3. **Hardcoded secrets in settings** — values in `env` blocks, `mcpServers
   .*.env`, or hook commands that look like tokens (long base64-ish
   strings, anything matching `(?i)(token|secret|key|password|credential)`
   = literal value rather than `${ENV_VAR}` reference).

4. **MCP servers on suspicious endpoints** — `mcpServers.*.url` or
   `mcpServers.*.command` pointing to non-HTTPS URLs, raw IPs, or
   commands that download-and-exec.

5. **Skills with over-broad allowed-tools** — `allowed-tools: ["*"]` or
   `allowed-tools: ["Bash"]` without scope restriction in any standalone
   SKILL.md or plugin skill. Any skill that grants Bash unrestricted is a
   foot-cannon.

6. **Stale references** — rules referencing skills that no longer exist
   (rules mentioning a skill name that's not in the inventory). These
   aren't security bugs but cause silent confusion.

7. **Project-scope rules contradicting user-scope rules** — same rule
   filename in both, different content. Project wins on conflict per spec.

OUTPUT FORMAT — structured markdown sections:

## High-severity findings (action recommended)
- One bullet per finding with: file path, line number if applicable,
  what's wrong, why it matters, suggested fix.

## Medium-severity findings (worth a look)
- Same shape.

## Low-severity / informational
- Same shape.

## False positives I considered but cleared
- One-liner per skipped pattern with reasoning. (Helps the user trust the
  pass — they can see what was checked, not just what was flagged.)

DO NOT modify any files. DO NOT recommend automatic fixes for medium/low
items. The user makes every call.
```

The output of this agent is presented in the HTML decision UI as a separate "🔐 Security findings" section ABOVE the regular keep/delete cards. High-severity findings get their own decision toggle: `fix now` / `acknowledge / skip`.

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
