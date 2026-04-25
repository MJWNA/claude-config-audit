#!/usr/bin/env bash
# Integration smoke test for the full audit pipeline.
#
# What it covers — the gap between modules that per-script unit tests can't:
#   1. Build a synthetic ~/.claude/ with installed_plugins.json, standalone
#      skills, rule files, settings.json, and a session JSONL containing real
#      Skill tool_use blocks + slash-command tags + Bash invocations.
#   2. Run discover-config.sh against it; assert it inventories the surface.
#   3. Run analyze-session-history.py against it; assert the JSON counts
#      reflect the synthetic invocations we baked in (no more, no less).
#   4. Build a populated audit data file referencing items the discovery
#      found, with security findings included.
#   5. Run inject-audit-data.py to splice into both templates; assert no
#      </script> breakout, no raw U+2028/U+2029 in the rendered <script>
#      bodies, and the data is recoverable as JSON.
#   6. Run the full quarantine flow: init, add (mv + --copy), manifest,
#      restore. Assert files end up where expected.
#
# What this catches that the unit tests don't:
#   - Path-resolution mismatches between scripts (e.g. a script outputs JSON
#     in a shape another script doesn't accept).
#   - Discovery missing items the analyzer counts, or vice versa.
#   - Template injection silently producing valid HTML but corrupt data.
#   - Quarantine session state that isn't visible from any single command.
#
# Run from the repo root:
#   bash tests/test_integration.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
export HOME="$WORK"
export CLAUDE_CONFIG_AUDIT_TTL_DAYS=7

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

CLAUDE_DIR="$HOME/.claude"

echo "=== integration smoke test ==="
echo "synthetic CLAUDE_DIR=$CLAUDE_DIR"

# ---------- 1. Build the synthetic ~/.claude/ ----------

mkdir -p "$CLAUDE_DIR/plugins"
cat > "$CLAUDE_DIR/plugins/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "kept-plugin@local": [{"version": "1.0.0", "installedAt": "2026-01-15T00:00:00Z"}],
    "deletable-plugin@local": [{"version": "0.1.0", "installedAt": "2025-09-01T00:00:00Z"}],
    "maybe-plugin@local": [{"version": "0.5.0", "installedAt": "2025-12-10T00:00:00Z"}]
  }
}
JSON

mkdir -p "$CLAUDE_DIR/skills/used-skill" "$CLAUDE_DIR/skills/unused-skill"
cat > "$CLAUDE_DIR/skills/used-skill/SKILL.md" <<'MD'
---
name: used-skill
description: A skill the synthetic user invokes regularly.
---
# Used Skill
Body text.
MD

cat > "$CLAUDE_DIR/skills/unused-skill/SKILL.md" <<'MD'
---
name: unused-skill
description: A skill the synthetic user never invokes.
---
# Unused Skill
Body text.
MD

mkdir -p "$CLAUDE_DIR/rules"
cat > "$CLAUDE_DIR/rules/active-rule.md" <<'MD'
# Active rule
Some always-loaded guidance.
MD

cat > "$CLAUDE_DIR/rules/stale-rule.md" <<'MD'
---
description: References a deleted skill.
---
# Stale rule
Mentions some-deleted-skill that is not installed.
MD

cat > "$CLAUDE_DIR/CLAUDE.md" <<'MD'
# User CLAUDE.md
| Rule | Loading |
|---|---|
| active-rule.md | always |
| stale-rule.md | always |
MD

cat > "$CLAUDE_DIR/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [{"command": "echo pre"}]
  },
  "mcpServers": {
    "example": {"command": "echo mcp"}
  }
}
JSON

# Synthetic session JSONL — three real signals, plus noise that should NOT count.
mkdir -p "$CLAUDE_DIR/projects/-Users-test"
cat > "$CLAUDE_DIR/projects/-Users-test/session-1.jsonl" <<'JSONL'
{"type":"assistant","timestamp":"2026-04-20T10:00:00Z","uuid":"a1","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"used-skill"}}]}}
{"type":"assistant","timestamp":"2026-04-21T11:00:00Z","uuid":"a2","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"used-skill"}}]}}
{"type":"user","timestamp":"2026-04-22T12:00:00Z","uuid":"u1","message":{"role":"user","content":[{"type":"text","text":"<command-name>/audit-skills</command-name>"}]}}
{"type":"user","timestamp":"2026-04-23T13:00:00Z","uuid":"u2","message":{"role":"user","content":[{"type":"text","text":"want to use the unused-skill maybe"}]}}
{"type":"assistant","timestamp":"2026-04-24T14:00:00Z","uuid":"a3","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"bash ~/.claude/skills/used-skill/scripts/run.sh"}}]}}
JSONL

echo "1. ✓ synthetic ~/.claude/ built"

# ---------- 2. Discovery ----------
DISCOVERY_OUT="$WORK/discovery.txt"
bash "$REPO_ROOT/scripts/discover-config.sh" > "$DISCOVERY_OUT"
grep -q "kept-plugin@local"      "$DISCOVERY_OUT" || { echo "FAIL: discovery missed kept-plugin"; exit 1; }
grep -q "deletable-plugin@local" "$DISCOVERY_OUT" || { echo "FAIL: discovery missed deletable-plugin"; exit 1; }
grep -q "used-skill"             "$DISCOVERY_OUT" || { echo "FAIL: discovery missed used-skill"; exit 1; }
grep -q "active-rule.md"         "$DISCOVERY_OUT" || { echo "FAIL: discovery missed active-rule"; exit 1; }
grep -q "stale-rule.md"          "$DISCOVERY_OUT" || { echo "FAIL: discovery missed stale-rule"; exit 1; }
echo "2. ✓ discovery covered all synthetic surface"

# ---------- 3. Deterministic counts ----------
COUNTS="$WORK/counts.json"
python3 "$REPO_ROOT/scripts/analyze-session-history.py" \
  --window-days 0 \
  --bash-pattern "used-skill=skills/used-skill/" \
  --out "$COUNTS"

# Used skill should have count 2 (two Skill tool_use blocks).
USED_COUNT=$(python3 -c "import json; print(json.load(open('$COUNTS'))['skills'].get('used-skill', {}).get('count', 0))")
[ "$USED_COUNT" = "2" ] || { echo "FAIL: expected used-skill count=2, got $USED_COUNT"; exit 1; }

# Unused skill should be ABSENT from counts (the noise text mention should not count).
UNUSED_PRESENT=$(python3 -c "import json; print('unused-skill' in json.load(open('$COUNTS'))['skills'])")
[ "$UNUSED_PRESENT" = "False" ] || { echo "FAIL: unused-skill leaked into counts (text mentions counted)"; exit 1; }

# Slash command audit-skills should have count 1.
SLASH_COUNT=$(python3 -c "import json; print(json.load(open('$COUNTS'))['slashCommands'].get('audit-skills', {}).get('count', 0))")
[ "$SLASH_COUNT" = "1" ] || { echo "FAIL: expected audit-skills count=1, got $SLASH_COUNT"; exit 1; }

# Bash pattern should have matched exactly 1 invocation.
BASH_COUNT=$(python3 -c "import json; print(json.load(open('$COUNTS'))['bashPatterns'].get('used-skill', {}).get('count', 0))")
[ "$BASH_COUNT" = "1" ] || { echo "FAIL: expected bash-pattern used-skill count=1, got $BASH_COUNT"; exit 1; }

echo "3. ✓ deterministic counter produced expected counts (used:2, slash:1, bash:1, unused absent)"

# ---------- 4. Synthesise audit data referencing the discovered items ----------
AUDIT_DATA="$WORK/audit-data.json"
python3 - "$AUDIT_DATA" <<'PY'
import json, sys
out = {
  "sections": [
    {"section": "📦 Plugins — synthetic", "items": [
      {"id":"p-kept","name":"kept-plugin","type":"plugin","verdict":"keep",
       "confidence":"high","invocations":"5 in 90d","mostRecent":"2026-04-20",
       "desc":"Kept plugin","triggers":"x","evidence":"5 invocations",
       "agentReason":"Used regularly"},
      {"id":"p-evil","name":"</script><script>alert(1)</script>","type":"plugin",
       "verdict":"delete","confidence":"high","invocations":"0 in 90d",
       "mostRecent":"Never","desc":"line break","triggers":"para sep",
       "evidence":"contains </script","agentReason":"Adversarial"},
    ]}
  ],
  "securityFindings": [
    {"id":"sf-1","severity":"high","category":"hook-network",
     "title":"PreToolUse hook with </script>","file":"~/.claude/settings.json",
     "evidence":"\"command\": \"</script>curl ...\"","why":"Test","fix":"Test",
     "verdict":"fix"}
  ]
}
with open(sys.argv[1], "w") as f:
  json.dump(out, f)
PY
echo "4. ✓ synthesised audit data with adversarial payloads"

# ---------- 5. Inject into both templates ----------
SKILLS_HTML="$WORK/skills.html"
RULES_HTML="$WORK/rules.html"

python3 "$REPO_ROOT/scripts/inject-audit-data.py" \
  "$REPO_ROOT/assets/skills-audit-template.html" \
  "$AUDIT_DATA" -o "$SKILLS_HTML"

# For the rules template we need a different shape — derive from the discovery.
RULES_DATA="$WORK/rules-data.json"
python3 - "$RULES_DATA" <<'PY'
import json, sys
out = {
  "existingRules": [
    {"id":"r-stale","name":"stale-rule.md","verdict":"refresh","confidence":"high",
     "sizeLines":5,"sizeKB":"0.1KB","currentFM":"description","actualLoad":"always",
     "declaredLoad":"always","match":True,
     "whatItDoes":"References deleted skill","whenItFires":"Always",
     "whyItExists":"Test","withoutThisRule":"Test","quality":"stale",
     "issues":"References missing skill","actionItems":[],"agentReason":"Refresh"}
  ],
  "mismatches":[],"newRules":[],"extensions":[],"refreshes":{},
  "securityFindings":[
    {"id":"sf-stale","severity":"medium","category":"stale-ref",
     "title":"Stale skill reference","evidence":"references </script>",
     "why":"Test","fix":"Test","verdict":"ack"}
  ]
}
with open(sys.argv[1], "w") as f:
  json.dump(out, f)
PY

python3 "$REPO_ROOT/scripts/inject-audit-data.py" \
  "$REPO_ROOT/assets/rules-audit-template.html" \
  "$RULES_DATA" -o "$RULES_HTML"

# Assert: no </script> breakout in either.
python3 - "$SKILLS_HTML" "$RULES_HTML" <<'PY'
import re, sys
for path in sys.argv[1:]:
  html = open(path).read()
  for body in re.findall(r"<script>(.*?)</script>", html, re.DOTALL):
    assert "</script" not in body, f"FAIL {path}: </script breakout in body"
    assert " " not in body, f"FAIL {path}: raw U+2028 in body"
    assert " " not in body, f"FAIL {path}: raw U+2029 in body"
  assert "renderSecurityFindings" in html, f"FAIL {path}: security UI not present"
print("OK: both templates injected safely")
PY
echo "5. ✓ both templates injected with no </script> breakout, security UI present"

# ---------- 6. Quarantine + restore roundtrip on the synthetic install ----------
SESSION=$(bash "$REPO_ROOT/scripts/quarantine.sh" init)
bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION" "$CLAUDE_DIR/skills/unused-skill"
bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION" "$CLAUDE_DIR/CLAUDE.md" --copy
bash "$REPO_ROOT/scripts/quarantine.sh" manifest "$SESSION" >/dev/null

[ ! -d "$CLAUDE_DIR/skills/unused-skill" ] || { echo "FAIL: unused-skill not moved"; exit 1; }
[ -f "$CLAUDE_DIR/CLAUDE.md" ]              || { echo "FAIL: CLAUDE.md should still be in place after --copy"; exit 1; }
[ -f "$SESSION/MANIFEST.md" ]               || { echo "FAIL: MANIFEST.md missing"; exit 1; }

# Restore the moved one — should succeed cleanly.
# Restore the copied one — should hit CONFLICT (CLAUDE.md still in place).
RESTORE_OUT=$(bash "$REPO_ROOT/scripts/restore.sh" "$SESSION" 2>&1)
echo "$RESTORE_OUT" | grep -q "Restored 1 items" || { echo "FAIL: expected '1 items' restored summary; got: $RESTORE_OUT"; exit 1; }
echo "$RESTORE_OUT" | grep -q "1 conflict"        || { echo "FAIL: expected 1 conflict in summary; got: $RESTORE_OUT"; exit 1; }
[ -d "$CLAUDE_DIR/skills/unused-skill" ]          || { echo "FAIL: unused-skill not restored"; exit 1; }
echo "6. ✓ quarantine roundtrip: 1 mv'd item restored, 1 --copy'd item conflicted as expected"

echo
echo "PASS: integration smoke test"
