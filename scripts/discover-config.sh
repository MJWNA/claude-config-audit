#!/usr/bin/env bash
# Inventory the current Claude Code installation and (optionally) the
# project-scope config in $PWD/.claude/.
#
# Usage:
#   discover-config.sh           # user-scope only
#   discover-config.sh --project # also scan $PWD/.claude/
#
# Output is consumed by the skill to build agent prompts. Cross-platform:
# tested on macOS (BSD coreutils) and Linux (GNU coreutils).

# Deliberately not -e: discover-config emits findings as it walks (the agents
# downstream tolerate missing surfaces — empty rules, no plugins, etc.) and
# treats absence as data, not an error. pipefail catches the cases where a
# pipeline like `find ... | wc -l` would silently return 0 on a permission
# error mid-walk.
set -uo pipefail

CLAUDE_DIR="$HOME/.claude"
INCLUDE_PROJECT=false

for arg in "$@"; do
  case "$arg" in
    --project) INCLUDE_PROJECT=true ;;
    --help|-h)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      printf 'unknown arg: %s (try --help)\n' "$arg" >&2
      exit 2
      ;;
  esac
done

# --- Portable file mtime (BSD vs GNU) ---
# stat -f is BSD/macOS; stat -c is GNU/Linux. We probe once and use whichever
# works. Falls back to `find -printf '%T@'` on systems where both fail.
file_mtime() {
  local path="$1"
  local m
  m=$(stat -c '%Y' "$path" 2>/dev/null) || \
  m=$(stat -f '%m' "$path" 2>/dev/null) || \
  m=$(find "$path" -maxdepth 0 -printf '%T@\n' 2>/dev/null | cut -d. -f1) || \
  m=""
  printf '%s' "$m"
}

# --- Portable ISO date for an mtime ---
mtime_to_date() {
  local m="$1"
  date -r "$m" "+%Y-%m-%d" 2>/dev/null || date -d "@$m" "+%Y-%m-%d" 2>/dev/null || printf '?'
}

# --- Scan a single config dir (user-scope or project-scope) ---
# Args: $1 = label, $2 = base dir (e.g. ~/.claude or ./.claude)
scan_config_dir() {
  local label="$1"
  local base="$2"

  printf '\n=== %s — %s ===\n\n' "$label" "$base"

  # Plugins
  printf '## Plugins (from installed_plugins.json)\n'
  local manifest="$base/plugins/installed_plugins.json"
  if [ -f "$manifest" ]; then
    python3 - "$manifest" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception as e:
    print(f"  (could not parse manifest: {e})")
    sys.exit(0)
plugins = d.get('plugins', {})
print(f"Total: {len(plugins)}")
print()
for key in sorted(plugins.keys()):
    entries = plugins[key]
    if entries:
        e = entries[0]
        version = e.get('version', '?')
        installed_at = (e.get('installedAt') or '?')[:10]
        print(f"  - {key} (v{version}, installed {installed_at})")
PY
  else
    printf '  (no installed_plugins.json found)\n'
  fi
  printf '\n'

  # Standalone skills
  printf '## Standalone skills (%s/skills/)\n' "$base"
  local skills_dir="$base/skills"
  if [ -d "$skills_dir" ]; then
    # Safe iteration: glob, not parsed `ls`. Handles spaces/newlines/special chars.
    local count=0
    local skill skill_md desc
    shopt -s nullglob 2>/dev/null || true
    for skill in "$skills_dir"/*/; do
      count=$((count + 1))
    done
    printf 'Total: %s\n\n' "$count"
    for skill in "$skills_dir"/*/; do
      [ -d "$skill" ] || continue
      local name
      name=$(basename "$skill")
      skill_md="$skill/SKILL.md"
      if [ -f "$skill_md" ]; then
        # Pull first description line, strip yaml quoting, cap at 100 chars.
        desc=$(awk '/^description:/{sub(/^description: */,""); print; exit}' "$skill_md" 2>/dev/null \
              | sed -e "s/^['\"]//; s/['\"]$//" \
              | cut -c1-100)
        printf '  - %s — %s\n' "$name" "$desc"
      else
        printf '  - %s (no SKILL.md)\n' "$name"
      fi
    done
  else
    printf '  (no %s/skills/ directory)\n' "$base"
  fi
  printf '\n'

  # Rules — discovered RECURSIVELY per the official Claude Code spec.
  # https://code.claude.com/docs/en/memory and the .claude/rules/ folder docs
  # confirm subdirectories are walked: a rule at `frontend/react.md` loads
  # the same way as a rule at the root. Earlier versions of this script used
  # `*.md` (one level) and missed nested rules — important because a skill
  # that audits "every rule" must actually see every rule.
  printf '## Rules (%s/rules/)\n' "$base"
  local rules_dir="$base/rules"
  if [ -d "$rules_dir" ]; then
    local rule lines bytes has_fm
    local rcount
    rcount=$(find "$rules_dir" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    printf 'Total: %s\n\n' "$rcount"
    # Rule paths are emitted relative to rules_dir so the user sees the
    # subdirectory structure, e.g. `frontend/react.md` not just `react.md`.
    while IFS= read -r rule; do
      lines=$(wc -l < "$rule" | tr -d ' ')
      bytes=$(wc -c < "$rule" | tr -d ' ')
      has_fm="no"
      [ "$(head -1 "$rule" 2>/dev/null)" = "---" ] && has_fm="yes"
      local rel="${rule#$rules_dir/}"
      printf '  - %s (%s lines, %s bytes, frontmatter: %s)\n' \
        "$rel" "$lines" "$bytes" "$has_fm"
    done < <(find "$rules_dir" -type f -name '*.md' 2>/dev/null | sort)
  else
    printf '  (no %s/rules/ directory)\n' "$base"
  fi
  printf '\n'

  # Hooks (settings.json sniff — flag for security review, never modify)
  printf '## Hooks + MCP servers (settings.json)\n'
  local found_settings=false
  for settings in "$base/settings.json" "$base/settings.local.json"; do
    if [ -f "$settings" ]; then
      found_settings=true
      python3 - "$settings" <<'PY'
import json, sys, os
path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
except Exception as e:
    print(f"  {os.path.basename(path)}: parse error ({e})")
    sys.exit(0)
hooks = d.get('hooks', {}) or {}
mcps  = d.get('mcpServers', {}) or {}
hook_count = sum(len(v) if isinstance(v, list) else 1 for v in hooks.values())
print(f"  {os.path.basename(path)}: {hook_count} hook handlers across {len(hooks)} events, {len(mcps)} MCP servers")
PY
    fi
  done
  $found_settings || printf '  (no settings files found)\n'
  printf '\n'
}

# --- Session history depth (user-scope only) ---
session_history_summary() {
  printf '## Session history\n'
  if [ -d "$CLAUDE_DIR/projects" ]; then
    local total
    total=$(find "$CLAUDE_DIR/projects" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
    printf 'Total Claude Code session files: %s\n' "$total"
    if [ "$total" -gt 0 ]; then
      # Find oldest jsonl by mtime, portably.
      local oldest_path oldest_m
      oldest_path=$(find "$CLAUDE_DIR/projects" -name '*.jsonl' -print 2>/dev/null \
        | while IFS= read -r p; do
            m=$(file_mtime "$p")
            [ -n "$m" ] && printf '%s\t%s\n' "$m" "$p"
          done \
        | sort -n | head -1 | cut -f2-)
      if [ -n "$oldest_path" ]; then
        oldest_m=$(file_mtime "$oldest_path")
        printf 'Oldest session: %s\n' "$(mtime_to_date "$oldest_m")"
      fi
    fi
  else
    printf '  (no %s/projects/ — limited session-history evidence)\n' "$CLAUDE_DIR"
  fi
}

# --- Audit history (decision memory across runs) ---
audit_history_summary() {
  printf '## Audit history\n'
  local history_dir="$CLAUDE_DIR/.audit-history"
  if [ -d "$history_dir" ]; then
    local count
    count=$(find "$history_dir" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
    printf 'Previous audits on record: %s\n' "$count"
    if [ "$count" -gt 0 ]; then
      printf 'Most recent:\n'
      find "$history_dir" -name '*.json' -print 2>/dev/null \
        | while IFS= read -r p; do
            m=$(file_mtime "$p")
            [ -n "$m" ] && printf '%s\t%s\n' "$m" "$p"
          done \
        | sort -rn | head -3 \
        | while IFS=$'\t' read -r m p; do
            printf '  - %s (%s)\n' "$(basename "$p")" "$(mtime_to_date "$m")"
          done
    fi
  else
    printf '  (no previous audits — first run)\n'
  fi
}

# --- Quarantine status ---
quarantine_summary() {
  printf '## Quarantine\n'
  local q="$CLAUDE_DIR/.audit-quarantine"
  if [ -d "$q" ]; then
    local count
    count=$(find "$q" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    printf 'Quarantined items pending cleanup: %s\n' "$count"
    if [ "$count" -gt 0 ]; then
      find "$q" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | while IFS= read -r d; do
        printf '  - %s\n' "$(basename "$d")"
      done
    fi
  else
    printf '  (no quarantine — nothing pending restore)\n'
  fi
}

# --- Main ---
echo "=== Claude Code config discovery ==="

scan_config_dir "User-scope" "$CLAUDE_DIR"

if $INCLUDE_PROJECT; then
  if [ -d "$PWD/.claude" ]; then
    scan_config_dir "Project-scope ($PWD)" "$PWD/.claude"
  else
    printf '\n=== Project-scope — none found at %s/.claude ===\n' "$PWD"
  fi
fi

session_history_summary
printf '\n'
audit_history_summary
printf '\n'
quarantine_summary
printf '\n'

echo "=== Discovery complete ==="
