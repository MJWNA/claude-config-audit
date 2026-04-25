# Extending the Skill

How to customise the workflow for your team or your own preferences.

The skill is opinionated about workflow but the implementation details are accessible. Here's where to look for each kind of change.

## Different agent prompts

Edit:

- `references/skills-audit-workflow.md` — the skills-half prompt template
- `references/parallel-agent-patterns.md` — the rules-half four agent prompt templates
- `references/rules-audit-workflow.md` — the dispatch sequence + synthesis logic

The prompts are wrapped in fenced code blocks so they're easy to find. Every prompt has the same shape: context paragraph → item list → analysis instructions → output format.

If you want to add a fifth agent (e.g. a "performance impact" agent that estimates context-cost savings), add it to the dispatch sequence in `rules-audit-workflow.md` and update the synthesis step to handle the new finding.

## Different categorisation

Edit `references/skills-audit-workflow.md`'s "Phase 2 — Categorise for parallel dispatch" section. The defaults are:

- Core dev tooling
- Workspace / hooks / config
- Frontend / design
- Platform / infrastructure
- Communications
- Meta / skill authoring
- Domain-specific user skills

If your team works in finance and has very different categories, replace these. The skill doesn't hard-code them — it uses them as suggestions in the workflow guide.

## Different HTML styling

Both templates use vanilla CSS (no preprocessor, no build step). Edit the `<style>` block at the top.

Common customisations:

- **Brand colours** — replace the CSS custom properties at the top: `--accent`, `--keep`, `--delete`, etc.
- **Font** — change `font-family` in the `html, body` rule
- **Card layout** — adjust `.skill-header` (skills audit) or `.rule-header` (rules audit) — both use flexbox, so re-ordering items is easy
- **Light theme** — invert the `--bg`, `--surface`, `--text`, `--muted` values

The HTML uses no external assets (no fonts, no images, no scripts) — it's fully self-contained and works offline.

## Different output format

The "Generate Markdown" button calls `generateMarkdown()` in the template's `<script>`. Edit it to change what the user pastes back. Common customisations:

- Different section ordering
- Additional metadata (e.g. include the agent verdicts in the output for audit trail)
- A JSON output option alongside markdown (just add another textarea + button)

Just make sure the new format is parseable by Claude when the user pastes it back. The skill currently expects:

```
## 🗑️ Delete
- **<item-name>** ...

## ✅ Keep
- **<item-name>** ...

## 🤔 Maybe
- **<item-name>** ...
```

If you change the section emoji or the `**name**` pattern, also update the parsing logic in the workflow references.

## Different time window

Default: 90 days for session-history scans. Defined in the agent prompts in `parallel-agent-patterns.md`.

To change, find every "last 90 days" or "90-day window" in:

- `references/parallel-agent-patterns.md`
- `references/skills-audit-workflow.md`
- `references/rules-audit-workflow.md`

Replace with your preferred window. Shorter (30 days) gives sharper recency signal; longer (180 days) catches seasonal patterns. Most users want 60-90 days.

## Different prerequisites

Edit `scripts/verify-prerequisites.sh`. Common changes:

- Require git installed (if you want git-snapshot before audit)
- Require `gh` CLI (if your audit consults GitHub data)
- Require a specific Claude Code version (parse the output of `claude --version`)

Keep the script POSIX-compatible — don't add bashisms unless your team standardises on bash.

## Different discovery output

Edit `scripts/discover-config.sh`. The current output is a structured Markdown summary. Common changes:

- Add JSON output option for programmatic consumption
- Include plugin metadata (manifest fields beyond `version` and `installedAt`)
- Include rule frontmatter for each rule (extracted via `awk` between `---` lines)

The discovery output is consumed by Claude (not piped to another script), so any format the model can read works. Markdown is preferred for legibility.

## Adding a third audit half

Currently the skill audits two halves: skills+plugins and rules. If you want to add a third (e.g. project-scope rules audit, or settings.json audit), the pattern is:

1. Add a new reference playbook: `references/<halfname>-workflow.md`
2. Add a new HTML template: `assets/<halfname>-audit-template.html`
3. Update `SKILL.md` to mention the new half (in "When to run which half" section)
4. Update `docs/HOW-IT-WORKS.md` walkthrough

The two existing halves are independent enough that a third can slot in without touching them.

## Skipping the HTML

If you want a no-HTML version of the skill (for users who prefer chat decisions), the workflow still works — Claude can present each item in chat with the agent verdict and ask for keep/delete/maybe per item.

The downside: 50 items × chat round-trips × user attention drift = much worse decision quality. Recommended only for small audits (10-15 items).

To implement: skip the "Build HTML" step and instead present items in chat 5-10 at a time, ask for decisions, then synthesise to markdown manually.

## Forking vs contributing back

If your customisation is generally useful (different agent prompts that produce sharper analysis, additional safety rails, better HTML interactions), please open a PR. The repo is opinionated about workflow but flexible about content quality.

If your customisation is specific to your team (your category names, your colour scheme, your naming conventions), fork. The skill is MIT licensed.
