#!/usr/bin/env bash
# Quarantine + restore roundtrip test.
#
# Builds a fake ~/.claude/ in a tmp dir, populates it with a "skill" and a
# "plugin cache dir", quarantines them via scripts/quarantine.sh, then
# restores them via scripts/restore.sh. Asserts the files are back where
# they started.
#
# Run from the repo root:
#   bash tests/test_quarantine_roundtrip.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
export HOME="$WORK"
export CLAUDE_CONFIG_AUDIT_TTL_DAYS=7

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$HOME/.claude/skills/example-skill"
mkdir -p "$HOME/.claude/plugins/cache/foo/example-plugin"
echo "skill content" > "$HOME/.claude/skills/example-skill/SKILL.md"
echo '{"v":"1"}' > "$HOME/.claude/plugins/cache/foo/example-plugin/plugin.json"

echo "1. init quarantine session"
SESSION="$(bash "$REPO_ROOT/scripts/quarantine.sh" init)"
[ -d "$SESSION" ] || { echo "FAIL: session not created"; exit 1; }

echo "2. quarantine the skill"
bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION" "$HOME/.claude/skills/example-skill"
[ ! -d "$HOME/.claude/skills/example-skill" ] || { echo "FAIL: skill not moved"; exit 1; }

echo "3. quarantine the plugin cache"
bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION" "$HOME/.claude/plugins/cache/foo/example-plugin"
[ ! -d "$HOME/.claude/plugins/cache/foo/example-plugin" ] || { echo "FAIL: cache not moved"; exit 1; }

echo "4. write manifest"
bash "$REPO_ROOT/scripts/quarantine.sh" manifest "$SESSION" >/dev/null
[ -f "$SESSION/MANIFEST.md" ] || { echo "FAIL: manifest missing"; exit 1; }

echo "5. boundary check — quarantine.sh refuses paths outside ~/.claude/"
# /etc/hosts exists on every platform we care about (macOS, Linux, WSL).
# `quarantine.sh add` should refuse this with exit 2 because the path is
# outside $CLAUDE_DIR.
if bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION" "/etc/hosts" 2>/dev/null; then
  echo "FAIL: quarantine.sh accepted a path outside ~/.claude/"
  exit 1
fi

echo "6. boundary check — quarantine.sh skips missing paths"
bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION" "$HOME/.claude/does-not-exist"

echo "7. restore"
bash "$REPO_ROOT/scripts/restore.sh" "$SESSION"

echo "8. verify everything is back where it started"
[ -f "$HOME/.claude/skills/example-skill/SKILL.md" ] || { echo "FAIL: skill not restored"; exit 1; }
[ -f "$HOME/.claude/plugins/cache/foo/example-plugin/plugin.json" ] || { echo "FAIL: cache not restored"; exit 1; }
[ "$(cat "$HOME/.claude/skills/example-skill/SKILL.md")" = "skill content" ] || \
  { echo "FAIL: skill content corrupted"; exit 1; }

echo "9. quarantine.sh purge respects TTL"
# Build a second, throwaway session and backdate it. The first session was
# restored cleanly in step 7 and is gone.
SESSION2="$(bash "$REPO_ROOT/scripts/quarantine.sh" init)"
[ -d "$SESSION2" ] || { echo "FAIL: second session not created"; exit 1; }
touch -t 200001010000 "$SESSION2"
CLAUDE_CONFIG_AUDIT_TTL_DAYS=1 bash "$REPO_ROOT/scripts/quarantine.sh" purge >/dev/null
[ ! -d "$SESSION2" ] || { echo "FAIL: purge didn't remove old session"; exit 1; }

echo
echo "PASS: quarantine roundtrip + boundary checks"
