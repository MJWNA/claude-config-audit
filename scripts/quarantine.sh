#!/usr/bin/env bash
# Quarantine deletions instead of `rm -rf`-ing them.
#
# Why: a destructive deletion against ~/.claude/ is psychologically heavy and
# users avoid running the audit at all. `mv` to a timestamped quarantine dir
# is reversible with a single command, so users actually clean up. The
# quarantine has a TTL: 7 days unless the user changes it.
#
# Usage:
#   quarantine.sh init                  # create a quarantine session, print its path
#   quarantine.sh add <session> <path>  # move <path> into the session
#   quarantine.sh manifest <session>    # write MANIFEST.md with restore instructions
#   quarantine.sh list                  # list existing quarantine sessions
#   quarantine.sh purge                 # delete sessions older than 7 days (idempotent)
#
# Every quarantined session is one directory under ~/.claude/.audit-quarantine/
# named with an ISO-ish timestamp. Inside it, paths are flattened with `--`
# separators so you can see what was where:
#
#   ~/.claude/.audit-quarantine/2026-04-25T20-30-00/
#     MANIFEST.md
#     plugins--installed_plugins.json     (file-level backup, copied not moved)
#     CLAUDE.md                            (file-level backup, copied not moved)
#     rules/                               (directory-level backup, copied not moved)
#     skills--meta-ads-expert/             (directory-level move from ~/.claude/skills/)
#     plugins--cache--marketplace--name--version/  (directory-level move from cache)

set -eu

CLAUDE_DIR="${HOME}/.claude"
QUARANTINE_BASE="${CLAUDE_DIR}/.audit-quarantine"
TTL_DAYS="${CLAUDE_CONFIG_AUDIT_TTL_DAYS:-7}"

cmd="${1:-help}"
shift || true

# --- Portable mtime helpers (BSD vs GNU) ---
file_mtime() {
  local path="$1"
  local m
  m=$(stat -c '%Y' "$path" 2>/dev/null) || \
  m=$(stat -f '%m' "$path" 2>/dev/null) || \
  m=""
  printf '%s' "$m"
}

now_epoch() { date +%s; }

# Used to encode an absolute path as a flat directory name. Drops the leading
# CLAUDE_DIR prefix and replaces '/' with '--'. Reversible by reading the
# MANIFEST or eyeballing.
flatten_path() {
  local path="$1"
  local rel="${path#$CLAUDE_DIR/}"
  printf '%s' "${rel//\//--}"
}

case "$cmd" in
  init)
    # ISO-ish timestamp, safe for filenames on every OS we care about.
    ts=$(date '+%Y-%m-%dT%H-%M-%S')
    session="${QUARANTINE_BASE}/${ts}"
    mkdir -p "$session"
    printf '%s' "$session"
    ;;

  add)
    session="${1:?usage: quarantine.sh add <session> <path>}"
    src="${2:?usage: quarantine.sh add <session> <path>}"
    [ -d "$session" ] || { printf 'no such quarantine session: %s\n' "$session" >&2; exit 1; }

    if [ ! -e "$src" ]; then
      printf 'skip: %s does not exist\n' "$src" >&2
      exit 0
    fi
    # Refuse to operate outside ~/.claude/. Hard guard against a malformed
    # caller passing /etc/passwd or similar.
    case "$src" in
      "$CLAUDE_DIR"/*) ;;
      *) printf 'refuse: %s is outside %s\n' "$src" "$CLAUDE_DIR" >&2; exit 2 ;;
    esac

    target="${session}/$(flatten_path "$src")"
    # `mv` for skill dirs and cache dirs (we want them gone from ~/.claude/).
    # `cp -R` for files we're backing up but leaving in place (manifest, rules
    # files, CLAUDE.md). The caller decides which by passing --copy.
    if [ "${3:-}" = "--copy" ]; then
      cp -R "$src" "$target"
      printf 'backed up: %s -> %s\n' "$src" "$target"
    else
      mv "$src" "$target"
      printf 'quarantined: %s -> %s\n' "$src" "$target"
    fi
    ;;

  manifest)
    session="${1:?usage: quarantine.sh manifest <session>}"
    [ -d "$session" ] || { printf 'no such session: %s\n' "$session" >&2; exit 1; }
    manifest_file="${session}/MANIFEST.md"
    {
      printf '# Audit quarantine — %s\n\n' "$(basename "$session")"
      printf 'Created: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
      printf 'TTL: %s days (auto-purge with `quarantine.sh purge`)\n\n' "$TTL_DAYS"
      printf '## Items in this quarantine\n\n'
      find "$session" -mindepth 1 -maxdepth 1 -not -name 'MANIFEST.md' -print | while IFS= read -r p; do
        # Reverse the flatten: turn `plugins--cache--name` back into the original-ish path.
        # This is informational, not authoritative — the MANIFEST text is for humans.
        flat=$(basename "$p")
        original=$(printf '%s' "$flat" | sed 's|--|/|g')
        printf -- '- %s\n  - **was at:** `~/.claude/%s`\n  - **size:** %s\n' \
          "$flat" "$original" "$(du -sh "$p" 2>/dev/null | awk '{print $1}')"
      done
      printf '\n## How to restore everything\n\n'
      printf '```bash\n'
      printf 'bash <skill-dir>/scripts/restore.sh %s\n' "$session"
      printf '```\n\n'
      printf '## How to restore a single item\n\n'
      printf '```bash\n'
      printf '# For directories that were moved:\n'
      printf 'mv "%s/<flattened-name>" ~/.claude/<original-path>\n\n' "$session"
      printf '# For files that were copied (manifest, CLAUDE.md, rules):\n'
      printf '# they are still at their original location — no restore needed\n'
      printf '```\n\n'
      printf '## How to permanently delete (after you are sure)\n\n'
      printf '```bash\nrm -rf %s\n```\n' "$session"
    } > "$manifest_file"
    printf '%s\n' "$manifest_file"
    ;;

  list)
    if [ ! -d "$QUARANTINE_BASE" ]; then
      printf '(no quarantine sessions)\n'
      exit 0
    fi
    find "$QUARANTINE_BASE" -mindepth 1 -maxdepth 1 -type d -print | sort | while IFS= read -r s; do
      m=$(file_mtime "$s")
      age_days="?"
      if [ -n "$m" ]; then
        now=$(now_epoch)
        age_days=$(( (now - m) / 86400 ))
      fi
      count=$(find "$s" -mindepth 1 -maxdepth 1 -not -name 'MANIFEST.md' | wc -l | tr -d ' ')
      printf '%s  age=%sd  items=%s\n' "$(basename "$s")" "$age_days" "$count"
    done
    ;;

  purge)
    if [ ! -d "$QUARANTINE_BASE" ]; then
      exit 0
    fi
    now=$(now_epoch)
    cutoff=$(( now - TTL_DAYS * 86400 ))
    purged=0
    find "$QUARANTINE_BASE" -mindepth 1 -maxdepth 1 -type d -print | while IFS= read -r s; do
      m=$(file_mtime "$s")
      [ -z "$m" ] && continue
      if [ "$m" -lt "$cutoff" ]; then
        rm -rf "$s"
        printf 'purged (>%sd): %s\n' "$TTL_DAYS" "$(basename "$s")"
        purged=$((purged + 1))
      fi
    done
    ;;

  help|*)
    sed -n '2,28p' "$0"
    ;;
esac
