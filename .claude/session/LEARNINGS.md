# Learnings Log

Gotchas, failed approaches, and edge cases discovered. Append-only, newest first.

---

## 2026-04-25 — XSS-escaping asymmetry is a worse signal than missing-entirely

**The gotcha:** v1's `rules-audit-template.html` had an `escapeHtml()` function and used it on three fields (`note`, `proposedContent`, `proposedSnippet`). The `skills-audit-template.html` had zero escaping. The rules template's seventeen *other* user-controlled interpolations (`whatItDoes`, `whenItFires`, `withoutThisRule`, `quality`, `agentReason`, `currentFM`, etc.) were also raw.
**Why:** it's worse than "we forgot about escaping" because it implies false confidence — someone thought about XSS once, wrote the helper, and then got distracted. The first-pass code review confirms "XSS is handled" and moves on, even though most of the interpolation surface is still vulnerable.
**Workaround:** v2 applies `escapeHtml()` uniformly to every interpolation in both templates. A defensive reading: "defence-in-depth always means *every* interpolation, never *some*." The skill-template helper is in the file even though it had to be added — better to standardise on one canonical escape function than rely on per-interpolation judgement.

---

## 2026-04-25 — `stat -f` vs `stat -c` portability — silent failure mode

**The gotcha:** v1's `discover-config.sh:79` used BSD `stat -f` to read file mtimes. On Linux/WSL this fails silently — the script keeps running, but the "oldest session" line just doesn't print. No error message, no warning. The user thinks the script worked.
**Why:** BSD coreutils (macOS) and GNU coreutils (Linux) have incompatible `stat` flag conventions. Bash scripts that target both need a fallback chain.
**Workaround:** v2 uses a probe-and-fallback pattern that tries GNU first, then BSD, then `find -printf`:
```bash
file_mtime() {
  local m
  m=$(stat -c '%Y' "$1" 2>/dev/null) || \
  m=$(stat -f '%m' "$1" 2>/dev/null) || \
  m=$(find "$1" -maxdepth 0 -printf '%T@\n' 2>/dev/null | cut -d. -f1) || \
  m=""
  printf '%s' "$m"
}
```
Same pattern for `date -r` (BSD) vs `date -d @` (GNU).

---

## 2026-04-25 — `for x in $(ls)` breaks on whitespace; safe glob iteration is mandatory

**The gotcha:** v1's `discover-config.sh:39, 59` iterated skills/rules with `for skill in $(ls -1 "$dir")` which silently breaks if any directory or filename contains spaces, tabs, or newlines. Common in user-installed skills with hyphenated/spaced names.
**Why:** word-splitting on `$(ls)` output is one of the canonical bash anti-patterns. The script *worked* in testing because no skill names had spaces, but the failure mode is silent corruption.
**Workaround:** v2 uses safe glob iteration: `for skill in "$dir"/*/; do [ -d "$skill" ] || continue; ...; done`. The `nullglob` shell option also enabled where supported so empty globs don't produce literal `*`.

---

## 2026-04-25 — Markdown export "embedded" content can vanish on conversation compaction

**The gotcha:** v1's rules markdown export emitted only `### <rule-name>\nSource: <X>\n` for new rules. The full `proposedContent` (the actual markdown that would land in the rule file) was assumed to still be in Claude's scrollback. If the user spent 30 minutes reviewing the HTML and the conversation compacted in the meantime, the rule bodies were gone — the export was technically valid but functionally useless.
**Why:** any workflow that reads from "the agent's context" rather than "the artefact the user receives" is fragile against context compaction. The HTML decision tool is an artefact; the conversation is not.
**Workaround:** v2's export embeds the full `proposedContent` in a `<details>` block per new rule. The export is now self-contained — Claude doesn't need to remember anything to execute it. Same fix applied to extensions (`proposedSnippet`).

---

## 2026-04-25 — Description-stuffing for triggering hurts spec compliance

**The gotcha:** v1's SKILL.md description was 1057 chars (33 over the 1024-char Agent Skills spec cap). The bulk of the overflow was a bolded list of 16+ trigger phrases ("audit my Claude config", "spring clean Claude", etc.) intended to maximise triggering accuracy. It probably *worked* for trigger accuracy but silently truncated trailing keywords on the loader side, and signalled SEO-style keyword-stuffing.
**Why:** spec-compliance and keyword-stuffing are pulling in opposite directions. The right fix isn't to compress the keywords — it's to use a different triggering mechanism (slash commands) and let the description focus on intent.
**Workaround:** v2 description is 877 chars, written as a coherent intent statement that covers a *broader* trigger landscape (hooks, MCPs, project-scope) than v1 did, without listing 16 paraphrases. Slash commands provide the deterministic alternative path.

---

## 2026-04-25 — Two prior audits converged on the same overall score (75-76/100); use that as calibration

**The gotcha:** I was tempted to either dismiss the prior audits as conceptual hand-waving or absorb them wholesale. Either extreme would have been wrong.
**Why:** they did agree on most of the substantive findings (description over spec, README/CHANGELOG drift, XSS risk, missing security pass, missing evals, no decision memory) — but they also diverged on severity weights and on a few specific factual claims (one audit said "the rules export markdown is incomplete" which was correct; one said "no jq fallback wired up" which was wrong — the script doesn't reference jq at all). The right move was to *verify every claim against the actual code* before agreeing or disagreeing.
**Workaround:** for any future external audit, the synthesis pass should always include a code-level verification step. Treat the audit as hypotheses, not findings.

---
