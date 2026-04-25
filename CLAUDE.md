# claude-config-audit — Maintainer Notes

This is a public Claude Code skill + plugin. Anyone installs it; everyone has a different setup. **Never hardcode specific skill names, plugin names, business names, or case-study numbers in any user-facing file** (SKILL.md, README.md, references/, docs/, examples/, evals/). Examples must use `<placeholder>` names. The skill discovers the user's installed neighbour skills at runtime by reading their actual `installed_plugins.json` and `~/.claude/skills/` directory — never by hardcoded name.

## Repo layout

- `SKILL.md` — main skill, frontmatter description must stay under 1024 chars per spec
- `assets/*-audit-template.html` — self-contained single-file decision UIs; every interpolation that comes from agent output must pass through `escapeHtml()`
- `commands/audit-skills.md`, `commands/audit-rules.md` — slash commands registered via `.claude-plugin/plugin.json`
- `references/` — progressive-disclosure playbooks loaded only when the corresponding phase is reached
- `scripts/` — bash + python; portable across macOS, Linux, WSL (BSD/GNU `stat` fallback already wired in `discover-config.sh`)
- `evals/evals.json` — 10 should-trigger + 10 should-not-trigger queries, kept current with the description

## When making changes

- Update `CHANGELOG.md` for any user-visible change. Follow [Keep a Changelog](https://keepachangelog.com/) format.
- If a change affects triggering, add or revise queries in `evals/evals.json`.
- HTML template changes: re-verify XSS escaping on every `innerHTML` write site.
- Bash changes: smoke-test on macOS (BSD `stat`) and at minimum manually trace the GNU fallback paths.

## Session continuity

This project uses `.claude/session/` for cross-session context.
**On session start**, read `.claude/session/HANDOFF.md` (first entry only) to pick up where the last session left off. Also skim DECISIONS.md and LEARNINGS.md headers for recent context.

## Releasing

- Branch: `release/vN.N.N` from `main`
- PR: title summarises the headline changes, body has Summary + Test plan
- Merge: `--merge` (not squash — the v2 commit message itself was 50+ lines worth keeping verbatim)
- Tag: not currently automated; manual `git tag` after merge if needed for release pages
