#!/usr/bin/env bash
# Verify the user's environment is ready for claude-config-audit.
# Exits 0 if everything is ready; non-zero with a clear message otherwise.

set -u

CLAUDE_DIR="$HOME/.claude"
issues=()

echo "=== claude-config-audit prerequisites ==="

# 1. Claude Code config directory exists
if [ ! -d "$CLAUDE_DIR" ]; then
  issues+=("$CLAUDE_DIR does not exist — is Claude Code installed?")
fi

# 2. At least one auditable directory exists
has_plugins=false
has_skills=false
has_rules=false

[ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ] && has_plugins=true
[ -d "$CLAUDE_DIR/skills" ] && [ "$(ls -A "$CLAUDE_DIR/skills" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && has_skills=true
[ -d "$CLAUDE_DIR/rules" ] && [ "$(ls -A "$CLAUDE_DIR/rules" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && has_rules=true

if ! $has_plugins && ! $has_skills && ! $has_rules; then
  issues+=("Nothing to audit — no plugins, no standalone skills, no user-scope rules found")
fi

# 3. Required tools
command -v python3 >/dev/null 2>&1 || issues+=("python3 not found — needed for JSON manipulation")
command -v ls >/dev/null 2>&1 || issues+=("ls not found — basic shell broken")

# 4. CWD is writable (for HTML output)
if [ ! -w "$PWD" ]; then
  issues+=("Current directory $PWD is not writable — the HTML audit tools need to land somewhere")
fi

# Report
if [ ${#issues[@]} -eq 0 ]; then
  echo "✅ All prerequisites met"
  echo ""
  echo "Detected:"
  $has_plugins && echo "  📦 Plugins manifest found"
  $has_skills && echo "  🎫 Standalone skills found ($(ls "$CLAUDE_DIR/skills" | wc -l | tr -d ' ') skills)"
  $has_rules && echo "  📐 User-scope rules found ($(ls "$CLAUDE_DIR/rules" | wc -l | tr -d ' ') rules)"
  echo ""
  echo "Ready to run audit."
  exit 0
else
  echo "❌ Issues found:"
  for issue in "${issues[@]}"; do
    echo "  - $issue"
  done
  exit 1
fi
