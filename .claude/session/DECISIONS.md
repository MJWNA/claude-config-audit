# Decisions Log

Architectural and design decisions with reasoning. Append-only, newest first.

---

## 2026-04-25 — Quarantine instead of `rm -rf` for all destructive operations

**Chose:** `mv` to `~/.claude/.audit-quarantine/<ISO-timestamp>/` with 7-day TTL and one-line restore script
**Over:** continuing v1's `rm -rf` with `.bak` backup of just `installed_plugins.json`
**Because:** the *psychological* weight of "delete" against the user's `~/.claude/` was the audit's biggest adoption blocker. Users who feel that weight don't run audits. `mv` to a quarantine dir is reversible enough that they actually clean up — which is the whole point. The file-level safety implication is identical (data is preserved either way), but the behavioural delta is the entire point.
**Context:** flagged by both prior third-party audits as the "biggest issue" / "single biggest UX improvement available". v1 admitted in `safety-protocol.md` that rule edits were "reversible only via the user's version control" — that was an honest doc, but a bad product.

---

## 2026-04-25 — Decision memory across runs as v2's biggest architectural addition

**Chose:** persist per-audit decisions to `~/.claude/.audit-history/<timestamp>--<half>.json` via `scripts/audit-history.py save/latest/diff`
**Over:** keeping each audit as a one-shot novelty
**Because:** v1 was a tool; v2 is a *practice*. The user runs it monthly, audit takes 4 minutes (only deltas), the config stays trim forever. This is where 5-star adoption lives. Every other v2 feature (confidence tiers, quarantine, security pass) is additive value on top of this foundation — without it, every audit starts from zero and the skill stays a one-shot novelty.
**Context:** explicitly identified as "the single most important iteration" in one of the prior audits. The implementation is small (~190 lines of Python + a JSON envelope embedded in the markdown export) but the behavioural change is large.

---

## 2026-04-25 — Runtime neighbour-skill discovery; never hardcode names

**Chose:** read the user's `~/.claude/plugins/installed_plugins.json` and `~/.claude/skills/` at runtime to discover what neighbour skills are installed; match by description-overlap; offer handoff
**Over:** hardcoding specific skill names like `claude-md-improver`, `hookify`, `claude-permissions-optimizer` (which were named in one of the prior audits as suggestions)
**Because:** the user explicitly clarified — "everyone's going to have different skills loaded into their own Claude. This isn't specifically for me. This is going to be a public repo skill for production." Hardcoding pins the skill to one user's setup and is meaningless for anyone else. Public-repo skills must work for any installer.
**Context:** drove a complete sweep of every reference to specific plugins/skills/businesses/case-study numbers across SKILL.md, README.md, all references, all docs, and the sample audit output. Replaced with `<placeholder>` names and runtime-discovery patterns.

---

## 2026-04-25 — Self-contained markdown export with embedded JSON envelope

**Chose:** rules export now embeds full `proposedContent` for new rules and full `proposedSnippet` for extensions inline; both halves end with `<!-- claude-config-audit:decisions { ... } -->` JSON envelope
**Over:** v1's "agent name + frequency only" export which assumed Claude still had the proposed content in scrollback
**Because:** v1's workflow broke on conversation compaction. If the conversation got long enough to compact between "user generates markdown in HTML" and "Claude writes the rule files", the rule bodies were lost. This is a real architectural fragility, not just a polish issue. The JSON envelope at the end is also what enables decision-memory across runs — `audit-history.py save` parses it directly.
**Context:** flagged by one of the prior audits as a workflow integrity problem rather than a docs gap.

---

## 2026-04-25 — Ship as plugin with slash commands, not just a description-matched skill

**Chose:** `.claude-plugin/plugin.json` + `commands/audit-skills.md` + `commands/audit-rules.md`
**Over:** continuing v1's description-only triggering
**Because:** description triggering is fragile (depends on phrasing, char-limit, keyword-stuffing risk) and conflicts with the spec's 1024-char description cap. Slash commands are deterministic — `/audit-skills` either fires or it doesn't, no "did the description match?" ambiguity. Also lower-friction: the user types four characters, not a paragraph.
**Context:** v1's description was 1057 chars (over the 1024 limit). Trimming to 877 chars meant dropping the "16+ trigger phrases" keyword blob — which would have hurt triggering accuracy if there weren't slash commands as a deterministic alternative.

---
