#!/usr/bin/env bash
# Restore items from a quarantine session back to their original locations.
#
# Usage:
#   restore.sh <session-dir>           # restore everything in the session
#   restore.sh <session-dir> --dry-run # show what would be restored without doing it
#
# This is the inverse of quarantine.sh add. It reverses the flattened naming
# convention (`a--b--c` → `a/b/c`) and `mv`s items back. Items that exist at
# the destination are NOT overwritten — they're flagged for the user to decide.

# pipefail catches errors mid-pipeline (e.g. `find ... | wc -l` where find
# hits a permission error) so we don't continue on under bad assumptions.
set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"

session="${1:?usage: restore.sh <session-dir> [--dry-run]}"
dry_run=false
[ "${2:-}" = "--dry-run" ] && dry_run=true

if [ ! -d "$session" ]; then
  printf 'no such session: %s\n' "$session" >&2
  exit 1
fi

# Refuse to operate on a session outside the quarantine base — defence in
# depth in case someone passes a random path.
case "$session" in
  "$CLAUDE_DIR"/.audit-quarantine/*) ;;
  *) printf 'refuse: %s is not a quarantine session\n' "$session" >&2; exit 2 ;;
esac

restored=0
conflicts=0

# Resolve a quarantined item to its original path. Prefers the sidecar
# `<item>.meta.json` (added in v2.3 — exact, lossless), falls back to the
# reverse-flatten of the basename (legacy — lossy for paths containing `--`).
# Using --copy items leave a meta.json so restore knows they were snapshots,
# not moves.
resolve_original() {
  local item="$1"
  local meta="${item}.meta.json"
  if [ -f "$meta" ]; then
    # Pass `$meta` through argv, never through string interpolation. A path
    # containing a single quote (e.g. a maliciously named skill or a legitimate
    # name with `'` in it) would otherwise either break the python parse or, in
    # a worst-case crafted form, execute attacker-chosen Python from the
    # quarantine session. argv-based passing is injection-immune by construction.
    python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['originalPath'])" "$meta"
  else
    # Legacy fallback for sessions created before v2.3.
    local flat
    flat=$(basename "$item")
    local rel
    rel=$(printf '%s' "$flat" | sed 's|--|/|g')
    printf '%s' "${CLAUDE_DIR}/${rel}"
  fi
}

# Use process substitution so the loop runs in the parent shell, not a
# subshell. With `find ... | while`, every increment to `restored` and
# `conflicts` would be lost when the subshell exits — the summary at the
# end would always print 0/0 regardless of what happened.
# We exclude *.meta.json sidecars and MANIFEST.md from the iteration; the
# items themselves are everything else at depth 1.
while IFS= read -r p; do
  case "$(basename "$p")" in
    MANIFEST.md|*.meta.json) continue ;;
  esac

  dest=$(resolve_original "$p")

  if [ -e "$dest" ]; then
    printf 'CONFLICT: %s already exists. Resolve manually:\n' "$dest"
    printf '  - keep current:  rm -rf %s %s.meta.json\n' "$p" "$p"
    printf '  - restore old:   rm -rf %s && mv %s %s && rm -f %s.meta.json\n' "$dest" "$p" "$dest" "$p"
    conflicts=$((conflicts + 1))
    continue
  fi

  if $dry_run; then
    printf 'would restore: %s -> %s\n' "$p" "$dest"
  else
    mkdir -p "$(dirname "$dest")"
    mv "$p" "$dest"
    rm -f "${p}.meta.json"
    printf 'restored: %s\n' "$dest"
    restored=$((restored + 1))
  fi
done < <(find "$session" -mindepth 1 -maxdepth 1 -not -name 'MANIFEST.md' -not -name '*.meta.json' -print)

# Summary line — visible to the user, useful for the rules-half flow where
# a partial restore (some restored, some conflicts to resolve) is the
# common case.
if $dry_run; then
  printf '\nDry run: would restore %d items (skipped: %d conflict(s))\n' "$restored" "$conflicts"
else
  printf '\nRestored %d items, %d conflict(s) require manual resolution\n' "$restored" "$conflicts"
fi

if ! $dry_run; then
  # If everything restored cleanly, remove the empty session dir (manifest only).
  remaining=$(find "$session" -mindepth 1 -not -name 'MANIFEST.md' -print 2>/dev/null | wc -l | tr -d ' ')
  if [ "$remaining" = "0" ]; then
    rm -f "${session}/MANIFEST.md"
    rmdir "$session" 2>/dev/null || true
    printf 'session emptied: %s\n' "$session"
  fi
fi
