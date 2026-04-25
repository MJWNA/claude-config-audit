# Changelog

All notable changes to claude-config-audit are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — 2026-04-25

Major release. Deletions are now reversible quarantine moves, decisions persist across runs, and the skill ships as a plugin with first-class slash commands. Every public-facing surface has been reviewed for portability — the skill works for any user with no hardcoded assumptions about what's installed.

### Added

- **Quarantine-based reversibility** — every "delete" is a `mv` to `~/.claude/.audit-quarantine/<ISO-timestamp>/` with a 7-day TTL and a one-line restore. `rm -rf` is no longer used in any normal flow. (`scripts/quarantine.sh`, `scripts/restore.sh`)
- **Decision memory across audits** — per-audit decisions persist to `~/.claude/.audit-history/<timestamp>--<half>.json`. The next audit reads the most recent entry and surfaces only deltas: items new since last time, items where invocation evidence has changed, snoozed items now due. (`scripts/audit-history.py`)
- **Security-pass agent** — dedicated 5th agent on both halves scanning hooks for shell-injection, MCPs for suspicious endpoints, settings for hardcoded tokens, skills for over-broad `allowed-tools`. Findings surface in a separate HTML section above the keep/delete cards.
- **Slash commands** — `/audit-skills` and `/audit-rules` go straight into the corresponding half. Plugin manifest at `.claude-plugin/plugin.json` registers them.
- **Project-scope coverage** — `discover-config.sh --project` includes `$PWD/.claude/`. The rules half flags user↔project rule contradictions and project-only patterns that could be promoted.
- **Confidence + reasonCodes per item** — both HTML templates show `🟢 high / 🟡 medium / 🔴 low` confidence chips and short reason-code tags so users can scan verdict quality at a glance.
- **Previous-decision hint** — when a previous audit exists, each card shows "📚 Last audit: you chose X" inline, eliminating re-justification of repeat decisions.
- **Self-contained markdown export** — the rules export embeds the full `proposedContent` for new rules and `proposedSnippet` for extensions. Both halves end with a JSON envelope (`<!-- claude-config-audit:decisions ... -->`) consumed by `audit-history.py`.
- **`evals/` directory** — 10 should-trigger and 10 should-not-trigger queries plus a methodology README. Compatible with skill-creator's description optimiser.
- **`SECURITY.md`** — explicit security policy and vulnerability-reporting flow.
- **GitHub issue templates** for bug reports and feature requests.

### Changed

- **Description trimmed under spec limit** — SKILL.md `description:` is now 877 chars (was 1057, over the 1024 spec cap). The keyword-stuffing trigger blob has been replaced with intent-based phrasing that covers a broader landscape (hooks, MCPs, project-scope) without listing 16 paraphrases.
- **Full XSS escaping pass on both HTML templates** — every interpolation that comes from agent output (skill names, descriptions, evidence quotes, rule content, frontmatter, action items, references) now runs through `escapeHtml()`. The audit data crosses an agent → template boundary and could contain HTML-shaped strings; they must render as text.
- **Portable bash** — `scripts/discover-config.sh` uses BSD/GNU `stat` fallback. Unsafe `for x in $(ls)` loops replaced with safe glob iteration. Tested on macOS, Linux, and WSL.
- **Backups expanded** — every file or directory the skill touches (rules, CLAUDE.md, settings, manifest) goes into the same quarantine session. v1 only snapshotted `installed_plugins.json`.
- **Skill works for any installer** — all references to specific plugins, skills, businesses, and case studies removed from public copy. Examples use `<placeholder>` names. The skill discovers neighbour skills at runtime by reading the user's installed manifest, never by hardcoded name.
- **Bucket categorisation framing** — `references/skills-audit-workflow.md` no longer prescribes specific bucket examples. It describes purpose categories and lets the skill cluster items at runtime based on what's actually installed.
- **`subagent_type` selection** — picks the best available subagent at runtime, falling back to `general-purpose`. v1 hardcoded specific plugin agent types.

### Fixed

- **Skills HTML XSS** — `${item.name}`, `${item.desc}`, `${item.triggers}`, `${item.mostRecent}`, `${item.evidence}` were interpolated raw into innerHTML. All now escaped via `escapeHtml()`.
- **Rules HTML partial XSS** — `whatItDoes`, `whenItFires`, `whyItExists`, `withoutThisRule`, `quality`, `issues`, `agentReason`, `currentFM`, `actualBehavior`, `rationale`, `contentSketch`, `evidence`, `frequency`, `cost`, `loadingMode`, `actionItems`, `whereInTarget`, `what`, `target` — were all interpolated raw. v2 escapes them.
- **Hand-rolled half-escape** — v1's note textarea did `replace(/</g,'&lt;')` only, missing `&` and `>`. Replaced with canonical `escapeHtml`.
- **Numerical drift between docs** — v1's README claimed a "64 → 53" case study while CHANGELOG claimed "50 → 32" (different snapshots of the same run). v2 drops specific numbers from public docs in favour of placeholder shapes.
- **Rules export missing `proposedContent`** — v1's rules markdown export emitted only the rule name and source. The actual rule body was assumed to still be in Claude's scrollback, which broke if the conversation compacted. v2 embeds full content.
- **BSD-only `stat -f`** — `discover-config.sh` line 79 of v1 silently failed on Linux/WSL.

### Migration from v1

- Re-install or pull the new commit. No data migration needed.
- Existing `~/.claude/plugins/installed_plugins.json.bak` files from v1 still work as backups.
- The first v2 audit is treated as a "first audit" by decision memory (no history yet); subsequent audits get the delta-only experience.

## [1.0.0] — 2026-04-25

### Added

- Initial release
- Skills audit half — parallel-agent scan + HTML decision tool + cleanup execution
- Rules audit half — parallel-agent scan + HTML decision tool with full proposed file content for new rule candidates
- Two HTML templates with localStorage persistence, mismatch filtering, bulk actions, and markdown export
- Five reference playbooks covering workflow, safety, parallel-agent patterns, and the official Claude Code rule spec (with citations to docs and known parser bugs in issues #17204, #23478, #13905)
- Two scripts for prerequisite checking and config discovery
- Four docs explaining philosophy, workflow, safety, and customisation
- Sample audit output documenting what a real audit run produces
