# Changelog

All notable changes to claude-config-audit are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] — 2026-04-25

Second-pass audit fixes from two independent LLM reviewers. The big one is plugin packaging — until this release, the SKILL.md at the repo root was only discovered by Claude Code under the standalone-skill install path. Plugin installs registered the slash commands but the skill itself (with all its trigger phrases for plain-language invocation) was invisible to plugin discovery, which expects `skills/<name>/SKILL.md`.

### Added

- **Plugin-canonical layout via symlinks** (`skills/claude-config-audit/`). Mirrors the root `SKILL.md`, `references/`, `scripts/`, and `assets/` so plugin install discovers the skill at the spec-required path while standalone install continues to read the canonical files at the repo root. Single source of truth, both install paths work. CI verifies the symlinks resolve on every push.
- **Integration smoke test** (`tests/test_integration.sh`). Builds a synthetic `~/.claude/` with installed plugins, standalone skills, rule files, settings, and session JSONL containing real `Skill` tool_use blocks + slash-command tags + Bash invocations. Runs discovery → deterministic counts → audit-data synthesis → template injection → quarantine + restore in sequence and asserts the outputs are coherent. Catches gaps between modules that the per-module unit tests can't see.
- **`plugin-layout` and `integration-smoke` CI jobs** (`.github/workflows/ci.yml`). The first asserts the symlinks resolve (canary for "someone clones without symlink support"); the second runs the end-to-end integration test on Ubuntu and macOS.
- **Restore summary line** (`scripts/restore.sh`). Prints `Restored N items, M conflict(s) require manual resolution` after the loop. The counters work now because the loop runs in the parent shell via process substitution; previously they were inside a `find ... | while` subshell and any summary would have shown 0/0.

### Changed

- **Quarantine session uniqueness.** `quarantine.sh init` was second-resolution: two `init` calls within the same second produced the same path and `mkdir -p` succeeded for both, silently sharing state. Now uses `mktemp -d "$BASE/$ts-XXXXXX"` so every session gets a unique 6-character random suffix and the dir is created atomically.
- **Rules workflow snapshot ordering.** `references/rules-audit-workflow.md` Phase 7 used to start with "write new rule files" — no quarantine snapshot before in-place edits. The slash command had the right ordering but a model following the detailed workflow would skip the safety rail. Phase 7 now opens with `quarantine.sh init` + `add ... --copy` for CLAUDE.md and every rule about to be edited, then proceeds with writes/edits.
- **Markdown export uses dynamic fence length.** Rules audit exports `proposedContent` (full proposed rule files) wrapped in code fences. If a proposed rule's content itself contained triple backticks (legitimate for rules about coding conventions), the outer fence closed early and the export became malformed. New `fenceWrap()` helper picks a fence length one longer than the longest backtick run inside the content, defaulting to 3.
- **`scripts/quarantine.sh purge` summary.** Same subshell-counter fix as `restore.sh` — prints `Purged N session(s)` after the loop.
- **`scripts/verify-prerequisites.sh` precedence.** The `[ A ] || [ B ] && C` lines are functionally correct (left-associative, equal-precedence `||`/`&&`) but read ambiguously. Replaced with explicit `if [ A ] || [ B ]; then C; fi` blocks.
- **`quarantine.sh add`'s `--copy` flag now documented.** The header usage block previously showed `add` with two positional args only; the `--copy` third-positional was undocumented. Now spelled out.
- **README install instructions** use `/plugin marketplace add` + `/plugin install` (the modern path) instead of manual `installed_plugins.json` editing. Standalone skill install path retained for users who don't want slash commands or are on older Claude Code versions.
- **README restore semantics** — previous wording oversold "one-line restore" without distinguishing `mv`'d items (deleted plugins/skills, which do reverse cleanly with one command) from `--copy`'d items (rule edits, where the original is still in place and `restore.sh` raises a CONFLICT prompt). Both flows are reversible; the docs now reflect that they're not the same flow.

### Fixed

- **Plugin-install plain-language triggering** — pre-2.2 plugin installs didn't surface `SKILL.md`, only the slash commands. The skill description with all its trigger phrases ("audit my Claude config", "spring clean Claude", etc.) was invisible. Now the plugin layout exposes SKILL.md at the canonical `skills/claude-config-audit/SKILL.md` path.
- **Quarantine session collision under same-second `init` calls** — see [Changed].
- **Unkept-promise gap between slash command and rules workflow** on snapshot ordering — see [Changed].
- **Markdown export breaking on rules whose proposed content contains code fences** — see [Changed].
- **Subshell-counter bug** that would have silently broken any `restore.sh` summary line a future maintainer added — see [Changed].

### Audit history

- v2.1.0 fixed the v2.0 unkept promises (rm -rf canonical sequence, security-findings UI, agent-invented counts, brittle plugin paths, no CI).
- v2.2.0 (this release) fixes structural and accuracy gaps surfaced by two independent LLM-conducted external audits — the most important being plugin packaging. The first audit (a 95/100 generous review) missed it; the second (8.4/10 critical review) caught it, alongside quarantine timestamp uniqueness, the rules-workflow snapshot order, the nested-fence export bug, and the restore-semantics overclaim.

## [2.1.0] — 2026-04-25

External-review fixes covering stale guidance, unkept v2 promises, and CI gaps. Six independent issues; each is fully addressed.

### Added

- **`scripts/inject-audit-data.py`** — safe HTML data injector. JSON-stringifies the audit data and escapes the four sequences unsafe inside `<script>` (`<`, `</`, U+2028, U+2029) before splicing it into either template. Both workflow docs and SKILL.md now mandate this script — hand-editing the placeholder is no longer the documented path because agent output may legitimately contain `</script>` strings or line-separator characters that would break the script tag if injected raw.
- **`scripts/analyze-session-history.py`** — deterministic invocation counter. Walks `~/.claude/projects/**/*.jsonl` and counts: `tool_use` blocks where `name=="Skill"` and `input.skill==<name>`, user messages containing `<command-name>/<name></command-name>` tags, and (optionally) `Bash` commands matching configurable `--bash-pattern label=regex` arguments. Emits JSON with per-skill `count`, `firstSeen`, `lastSeen`, and `byDay` breakdown. The bucket agents now interpret these counts instead of inventing them; `parallel-agent-patterns.md` instructs them not to re-grep the JSONL or disagree with the JSON.
- **Real security-findings UI** in both HTML decision tools. The CHANGELOG promised this in `2.0.0` but the templates didn't deliver it. Now they do: a separate `🔐 Security findings` section renders above the keep/delete cards, sorted high → medium → low, with three-state `fix-now / acknowledge / skip` toggles per finding. The data shape (severity, category, file, line, evidence, why, fix, verdict) is documented in a `SECURITY_DATA_SHAPE` comment in each template. Decisions persist via `localStorage` and the markdown export prepends a `## 🔐 Security findings` section so users can paste back their fix/ack/skip choices. The decision envelope adds a `securityDecisions` map for cross-run memory.
- **CI** — `.github/workflows/ci.yml`. Five jobs: `bash -n` syntax check, `shellcheck` (severity=warning), `python -m py_compile` matrixed across Python 3.9/3.11/3.12 on Ubuntu and macOS, `python -m unittest` on the same matrix, a quarantine/restore roundtrip test, and a template smoke test that asserts no `</script>` breakout in the rendered JS body.
- **`tests/`** — fixture tests for `inject-audit-data.py` (10 cases including adversarial payloads against both real templates), `audit-history.py` (envelope parsing, save/latest roundtrip, diff against prior audits), `analyze-session-history.py` (synthetic projects directory verifying skill counts, slash-command counts, time-window filtering, malformed-JSON resilience, bash-pattern regex matching), and a bash quarantine/restore roundtrip with boundary checks.
- **`${CLAUDE_PLUGIN_ROOT}` resolution in commands.** Both `commands/audit-skills.md` and `commands/audit-rules.md` now resolve the skill location through `SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/claude-config-audit}"` and reference scripts/assets through `$SKILL_DIR/...`. This makes `claude --plugin-dir <path>` testing work without needing a specific install path. README documents both install modes plus the `--plugin-dir` variant.

### Changed

- **Both HTML templates' injection points are now JSON, not JS.** The placeholder is `const __AUDIT_DATA__ = /* AUDIT_DATA_INJECTION_POINT */ {...};` (or `[...]` for the skills template), populated only via `inject-audit-data.py`. The runtime code derives `data` and `securityFindings` from that JSON, so the existing render paths continue to work.
- **Workflow docs** (`references/skills-audit-workflow.md`, `references/rules-audit-workflow.md`, `SKILL.md`) now teach the inject script as the only safe path for splicing audit data into a template. Hand-editing the placeholder is documented as wrong.
- **Phase 7 of `references/skills-audit-workflow.md` no longer shows `rm -rf` as the canonical execution sequence.** The deletion path is now `quarantine.sh init` → `add` → `manifest`, with explicit warning that previous versions of the document showed `rm -rf` and that guidance was wrong. The Phase 6 confirmation summary and Phase 9 restore instructions were updated to match — every "delete" surface in the document now reflects quarantine semantics.
- **Bucket-agent prompt template** in `references/parallel-agent-patterns.md` reorganised around the new deterministic counts file. The agent's job is now to interpret `count`, `lastSeen`, `byDay` from `/tmp/session-counts.json`, not to re-grep the JSONL. Anti-patterns (re-running grep, counting registry mentions, inventing missing counts) are explicit "DO NOT" items.

### Fixed

- **Stale `rm -rf` guidance contradicting the v2 quarantine promise** — `references/skills-audit-workflow.md` Phase 7 was the canonical-sequence example agents were most likely to copy. Now matches the SKILL.md and slash-command guidance everywhere.
- **HTML data injection accepted any agent output verbatim** — the injection point was a JS array literal, so agent strings containing `</script>` would break the script tag and any string containing U+2028/U+2029 would break JS source line termination. Agent output now flows through `safe_json_for_script()` which JSON-encodes and escapes those four sequences. Existing per-render `escapeHtml()` calls remain as defence in depth.
- **CHANGELOG claim "Findings surface in a separate HTML section above the keep/delete cards" was unkept** — the templates had no security-findings UI in 2.0.0. The Unreleased line item ships what the CHANGELOG already promised.
- **Plugin commands assumed a specific cwd-relative install path** — `commands/audit-skills.md` and `commands/audit-rules.md` referenced `claude-config-audit/SKILL.md` and `scripts/...` without rooting them, which broke under non-standard installs and `claude --plugin-dir` testing. All paths now route through `$SKILL_DIR` resolved from `${CLAUDE_PLUGIN_ROOT}`.
- **Subagent counts were ungrounded** — the bucket agents were instructed to count REAL invocations by greppping session history themselves. Agents sample, summarize, and occasionally invent. The deterministic counter `analyze-session-history.py` is now the single source of truth; agents interpret its output.
- **No CI** — first repo commit had no `.github/workflows/`. Bash syntax errors, broken shell quoting, and Python compile failures could land on `main` undetected. CI now exercises bash, Python, the quarantine roundtrip, and template injection on every push and PR.

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
