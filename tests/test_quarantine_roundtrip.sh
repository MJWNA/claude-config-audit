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

echo "10. v2.3 fix — name with '--' round-trips correctly"
# Pre-v2.3, the flatten/unflatten encoding (s|/|--|g) was lossy: a skill
# named foo--bar restored as foo/bar/. Now restore reads the .meta.json
# sidecar with the absolute original path, so the round-trip is exact
# regardless of what's in the filename.
mkdir -p "$HOME/.claude/skills/foo--bar/sub-rule"
echo "edge content" > "$HOME/.claude/skills/foo--bar/sub-rule/data.txt"
SESSION3="$(bash "$REPO_ROOT/scripts/quarantine.sh" init)"
bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION3" "$HOME/.claude/skills/foo--bar"
[ ! -d "$HOME/.claude/skills/foo--bar" ] || { echo "FAIL: foo--bar not moved"; exit 1; }
bash "$REPO_ROOT/scripts/restore.sh" "$SESSION3" >/dev/null
[ -f "$HOME/.claude/skills/foo--bar/sub-rule/data.txt" ] || \
  { echo "FAIL: foo--bar restored to wrong path"; find "$HOME/.claude" -type f; exit 1; }
[ ! -d "$HOME/.claude/skills/foo/bar" ] || \
  { echo "FAIL: foo--bar restored as foo/bar (the v2.2 bug returned)"; exit 1; }

echo "11. v2.3 fix — init produces unique paths in same second"
# Pre-v2.2, two init calls in the same second collided and silently shared
# state. v2.2 added mktemp -d -XXXXXX to fix this. Regression test asserts
# 5 rapid init calls produce 5 distinct paths.
PATHS=()
# Loop body doesn't reference the index; using `_` quiets shellcheck SC2034.
for _ in 1 2 3 4 5; do
  PATHS+=("$(bash "$REPO_ROOT/scripts/quarantine.sh" init)")
done
UNIQUE_COUNT=$(printf '%s\n' "${PATHS[@]}" | sort -u | wc -l | tr -d ' ')
[ "$UNIQUE_COUNT" = "5" ] || \
  { echo "FAIL: 5 init calls produced $UNIQUE_COUNT unique paths"; printf '%s\n' "${PATHS[@]}"; exit 1; }

echo "12. v2.3 fix — unknown command exits non-zero"
# Pre-v2.3, `quarantine.sh ad <session> <path>` (typo'd verb) hit the
# `help|*)` arm, printed usage, and exited 0 — an automation pipeline
# would proceed under the false impression the operation succeeded.
if bash "$REPO_ROOT/scripts/quarantine.sh" definitelynotacommand 2>/dev/null; then
  echo "FAIL: unknown command exited 0; should be non-zero"
  exit 1
fi

echo "13. v2.3.1 fix — flatten collision preserves both items"
# Pre-v2.3.1, two distinct source paths that flatten to the same name (e.g.
# `~/.claude/rules/foo--bar.md` and `~/.claude/rules/foo/bar.md` both flatten
# to `rules--foo--bar.md`) would silently overwrite each other in quarantine.
# The .meta.json sidecar made restore exact, but only if both items survived
# the on-disk write. Now we detect the collision and append a short hash so
# both items are preserved.
mkdir -p "$HOME/.claude/rules/foo"
echo "i am foo--bar.md" > "$HOME/.claude/rules/foo--bar.md"
echo "i am foo/bar.md"  > "$HOME/.claude/rules/foo/bar.md"
SESSION4="$(bash "$REPO_ROOT/scripts/quarantine.sh" init)"
bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION4" "$HOME/.claude/rules/foo--bar.md"
bash "$REPO_ROOT/scripts/quarantine.sh" add "$SESSION4" "$HOME/.claude/rules/foo/bar.md"
ITEMS_IN_SESSION=$(find "$SESSION4" -mindepth 1 -maxdepth 1 -not -name 'MANIFEST.md' -not -name '*.meta.json' -type f | wc -l | tr -d ' ')
[ "$ITEMS_IN_SESSION" = "2" ] || \
  { echo "FAIL: collision should have produced 2 items, got $ITEMS_IN_SESSION"; ls "$SESSION4"; exit 1; }
# Restore them both — destinations are clear because we moved both files out.
bash "$REPO_ROOT/scripts/restore.sh" "$SESSION4" >/dev/null
[ "$(cat "$HOME/.claude/rules/foo--bar.md" 2>/dev/null)" = "i am foo--bar.md" ] || \
  { echo "FAIL: foo--bar.md not restored correctly"; exit 1; }
[ "$(cat "$HOME/.claude/rules/foo/bar.md" 2>/dev/null)" = "i am foo/bar.md" ] || \
  { echo "FAIL: foo/bar.md not restored correctly"; exit 1; }

echo "14. v2.3.1 fix — restore handles single-quote in original path"
# Pre-v2.3.1, restore.sh interpolated the meta-file path into a python -c
# string with single quotes: `python3 -c "...open('$meta')..."`. A path
# containing a single quote (legitimate filename, or maliciously crafted)
# would either break the parse or, in a worst case, execute attacker-chosen
# Python. The fix passes the meta path via argv. This test plants a sidecar
# whose `originalPath` field describes a path with a single quote, and
# verifies restore reads it correctly without barfing.
SESSION5="$(bash "$REPO_ROOT/scripts/quarantine.sh" init)"
mkdir -p "$HOME/.claude/quirky"
# A real file lives in quarantine; the sidecar describes a target path
# containing a single quote. This exercises the python json.load path.
echo "quoted content" > "$SESSION5/quirky-item"
target_path="$HOME/.claude/quirky/it's-fine.md"
python3 -c "
import json, sys
meta_path = sys.argv[1]
target = sys.argv[2]
with open(meta_path, 'w') as f:
    json.dump({'originalPath': target, 'mode': 'move', 'quarantinedAt': '2026-04-26T00:00:00Z'}, f)
" "$SESSION5/quirky-item.meta.json" "$target_path"
# Restore: the script must read the sidecar via argv, not via shell
# interpolation, so the single quote in the JSON stays a literal.
bash "$REPO_ROOT/scripts/restore.sh" "$SESSION5" >/dev/null
[ -f "$target_path" ] || { echo "FAIL: single-quote-named restore failed"; ls "$HOME/.claude/quirky/"; exit 1; }
[ "$(cat "$target_path")" = "quoted content" ] || { echo "FAIL: single-quote-named content corrupted"; exit 1; }

echo
echo "PASS: quarantine roundtrip + boundary checks + v2.3 + v2.3.1 fixes"
