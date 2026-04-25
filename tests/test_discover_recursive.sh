#!/usr/bin/env bash
# Test that scripts/discover-config.sh discovers rules recursively (v2.3 fix).
#
# Pre-v2.3 the script used `for rule in "$rules_dir"/*.md; do` which only
# matched files at depth 1. The official Claude Code spec specifies rule
# discovery is recursive; a skill that audits "every rule" must actually
# see every rule, not just the top-level ones.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d)
export HOME="$WORK"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$HOME/.claude/rules/frontend/styling"
mkdir -p "$HOME/.claude/rules/backend"
echo "# top" > "$HOME/.claude/rules/top.md"
echo "# nested-1" > "$HOME/.claude/rules/frontend/react.md"
echo "# nested-2" > "$HOME/.claude/rules/frontend/styling/tailwind.md"
echo "# nested-3" > "$HOME/.claude/rules/backend/api.md"

out=$(bash "$REPO_ROOT/scripts/discover-config.sh")

# All four files must appear (Total: 4 + each by relative path).
echo "$out" | grep -q "Total: 4" || \
  { echo "FAIL: expected Total: 4 rules (got: $(echo "$out" | grep Total))"; echo "$out"; exit 1; }
echo "$out" | grep -q "top.md" || { echo "FAIL: top.md missed"; exit 1; }
echo "$out" | grep -q "frontend/react.md" || \
  { echo "FAIL: frontend/react.md missed (recursive walk broken)"; echo "$out"; exit 1; }
echo "$out" | grep -q "frontend/styling/tailwind.md" || \
  { echo "FAIL: deeply-nested tailwind.md missed"; exit 1; }
echo "$out" | grep -q "backend/api.md" || \
  { echo "FAIL: backend/api.md missed"; exit 1; }

echo "PASS: discover-config.sh walks rules recursively"
