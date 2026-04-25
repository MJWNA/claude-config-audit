#!/usr/bin/env bash
# Smoke test for scripts/verify-prerequisites.sh.
#
# Pre-v2.3 this script had no test coverage at all (test-coverage agent
# flagged it as P0). It gates whether any audit runs, so a regression that
# silently changes its emitted advice is exactly the kind of bug that's
# invisible until a user hits it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/verify-prerequisites.sh"

echo "=== verify-prerequisites smoke test ==="

# 1. Empty HOME → exit non-zero with "does not exist" hint.
WORK=$(mktemp -d)
out=$(HOME="$WORK" bash "$SCRIPT" 2>&1) && rc=0 || rc=$?
[ "$rc" != "0" ] || { echo "FAIL: empty HOME exited 0; expected non-zero"; exit 1; }
echo "$out" | grep -q "does not exist" || \
  { echo "FAIL: empty HOME message missing 'does not exist': $out"; exit 1; }
rm -rf "$WORK"

# 2. HOME with .claude but no auditable surface → exit 1 with "Nothing to audit".
WORK=$(mktemp -d)
mkdir -p "$WORK/.claude"
out=$(HOME="$WORK" bash "$SCRIPT" 2>&1) && rc=0 || rc=$?
[ "$rc" != "0" ] || { echo "FAIL: empty .claude exited 0"; exit 1; }
echo "$out" | grep -q "Nothing to audit" || \
  { echo "FAIL: empty .claude missed 'Nothing to audit': $out"; exit 1; }
rm -rf "$WORK"

# 3. With at least one rule file → succeeds (rc=0) and emits "Ready to run audit".
WORK=$(mktemp -d)
mkdir -p "$WORK/.claude/rules"
echo "# rule" > "$WORK/.claude/rules/test.md"
out=$(HOME="$WORK" bash "$SCRIPT" 2>&1) || { echo "FAIL: surfaced rule didn't pass: $out"; exit 1; }
echo "$out" | grep -q "Ready to run audit" || \
  { echo "FAIL: missing 'Ready to run audit': $out"; exit 1; }
echo "$out" | grep -q "User-scope rules found" || \
  { echo "FAIL: missing user-rules detection: $out"; exit 1; }
rm -rf "$WORK"

# 4. Rules at NESTED depth → also discovered (recursive find, v2.3 fix).
WORK=$(mktemp -d)
mkdir -p "$WORK/.claude/rules/frontend/styling"
echo "# nested" > "$WORK/.claude/rules/frontend/styling/tailwind.md"
out=$(HOME="$WORK" bash "$SCRIPT" 2>&1) || { echo "FAIL: nested rule didn't pass: $out"; exit 1; }
echo "$out" | grep -q "User-scope rules found" || \
  { echo "FAIL: nested rule not detected: $out"; exit 1; }
rm -rf "$WORK"

# 5. Quarantine pending warning fires.
WORK=$(mktemp -d)
mkdir -p "$WORK/.claude/rules" "$WORK/.claude/.audit-quarantine/2026-01-01-stale"
echo "# rule" > "$WORK/.claude/rules/test.md"
out=$(HOME="$WORK" bash "$SCRIPT" 2>&1)
echo "$out" | grep -q "currently quarantined" || \
  { echo "FAIL: pending quarantine warning missing: $out"; exit 1; }
rm -rf "$WORK"

echo
echo "PASS: verify-prerequisites smoke test"
