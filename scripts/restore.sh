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

set -eu

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

find "$session" -mindepth 1 -maxdepth 1 -not -name 'MANIFEST.md' -print | while IFS= read -r p; do
  flat=$(basename "$p")
  # Reverse flatten: `--` → `/`. This is the same encoding quarantine.sh uses.
  original_rel=$(printf '%s' "$flat" | sed 's|--|/|g')
  dest="${CLAUDE_DIR}/${original_rel}"

  if [ -e "$dest" ]; then
    printf 'CONFLICT: %s already exists. Resolve manually:\n' "$dest"
    printf '  - keep current:  rm -rf %s\n' "$p"
    printf '  - restore old:   rm -rf %s && mv %s %s\n' "$dest" "$p" "$dest"
    conflicts=$((conflicts + 1))
    continue
  fi

  if $dry_run; then
    printf 'would restore: %s -> %s\n' "$p" "$dest"
  else
    mkdir -p "$(dirname "$dest")"
    mv "$p" "$dest"
    printf 'restored: %s\n' "$dest"
    restored=$((restored + 1))
  fi
done

if ! $dry_run; then
  # If everything restored cleanly, remove the empty session dir (manifest only).
  remaining=$(find "$session" -mindepth 1 -not -name 'MANIFEST.md' -print 2>/dev/null | wc -l | tr -d ' ')
  if [ "$remaining" = "0" ]; then
    rm -f "${session}/MANIFEST.md"
    rmdir "$session" 2>/dev/null || true
    printf 'session emptied: %s\n' "$session"
  fi
fi
