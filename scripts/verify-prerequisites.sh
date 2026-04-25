#!/usr/bin/env bash
# Verify the user's environment is ready for claude-config-audit.
# Exits 0 if everything is ready; non-zero with a clear message otherwise.
#
# Cross-platform: macOS, Linux, WSL. POSIX-ish bash.

# Deliberately not -e here: the script's purpose is to *collect* every issue
# in a single pass and report all of them. -e would abort on the first failed
# check and the user would have to fix issues one-by-one across multiple runs.
# pipefail still applies so a `find ... | wc -l` that hits a permission error
# emits a real failure rather than a silent 0.
set -uo pipefail

CLAUDE_DIR="$HOME/.claude"
PROJECT_DIR="$PWD/.claude"
issues=()
warnings=()

echo "=== claude-config-audit prerequisites ==="

# 1. Claude Code config directory exists at user-scope.
if [ ! -d "$CLAUDE_DIR" ]; then
  issues+=("$CLAUDE_DIR does not exist — is Claude Code installed?")
fi

# 2. At least one auditable surface exists at user-scope OR project-scope.
has_user_plugins=false
has_user_skills=false
has_user_rules=false
has_user_hooks=false
has_proj_rules=false
has_proj_settings=false

[ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ] && has_user_plugins=true
[ -d "$CLAUDE_DIR/skills" ] && [ -n "$(find "$CLAUDE_DIR/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)" ] && has_user_skills=true
# Recursive: rules under .claude/rules/ are discovered at any depth per spec.
[ -d "$CLAUDE_DIR/rules" ]  && [ -n "$(find "$CLAUDE_DIR/rules"  -type f -name '*.md' 2>/dev/null | head -1)" ] && has_user_rules=true
# Use an explicit if-block so the OR-of-two-files / set-flag reads clearly.
# `[ A ] || [ B ] && C` is technically correct (bash treats || and && as
# left-associative with equal precedence, so this parses as (A||B)&&C) but
# the intent is opaque on first read.
if [ -f "$CLAUDE_DIR/settings.json" ] || [ -f "$CLAUDE_DIR/settings.local.json" ]; then
  has_user_hooks=true
fi

[ -d "$PROJECT_DIR/rules" ]  && [ -n "$(find "$PROJECT_DIR/rules" -type f -name '*.md' 2>/dev/null | head -1)" ] && has_proj_rules=true
if [ -f "$PROJECT_DIR/settings.json" ] || [ -f "$PROJECT_DIR/settings.local.json" ]; then
  has_proj_settings=true
fi

if ! $has_user_plugins && ! $has_user_skills && ! $has_user_rules && ! $has_user_hooks && ! $has_proj_rules && ! $has_proj_settings; then
  issues+=("Nothing to audit — no plugins, skills, rules, hooks, or project-scope config found")
fi

# 3. Required tools.
command -v python3 >/dev/null 2>&1 || issues+=("python3 not found — needed for atomic JSON manipulation")

# 4. CWD is writable (for HTML output).
if [ ! -w "$PWD" ]; then
  issues+=("Current directory $PWD is not writable — the HTML audit tools need to land somewhere")
fi

# 5. Session-history depth — warn if thin (verdicts will be biased).
if [ -d "$CLAUDE_DIR/projects" ]; then
  total_sessions=$(find "$CLAUDE_DIR/projects" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$total_sessions" -lt 50 ]; then
    warnings+=("Only $total_sessions session files in $CLAUDE_DIR/projects — agent verdicts will be biased toward 'looks underused'. A fresh install isn't worth auditing yet.")
  fi
fi

# 6. Quarantine pending restore — warn so user knows there's stuff to review.
if [ -d "$CLAUDE_DIR/.audit-quarantine" ]; then
  q_count=$(find "$CLAUDE_DIR/.audit-quarantine" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [ "$q_count" -gt 0 ]; then
    warnings+=("$q_count item(s) currently quarantined at $CLAUDE_DIR/.audit-quarantine/ — restore or purge before next audit if you want a clean state")
  fi
fi

# Report.
if [ ${#issues[@]} -eq 0 ]; then
  echo "✅ All prerequisites met"
  echo ""
  echo "Detected:"
  echo "  User-scope ($CLAUDE_DIR):"
  $has_user_plugins && echo "    📦 Plugin manifest found"
  $has_user_skills  && echo "    🎫 Standalone skills found"
  $has_user_rules   && echo "    📐 User-scope rules found"
  $has_user_hooks   && echo "    🪝 settings.json present (hooks + MCP servers may be defined)"
  if $has_proj_rules || $has_proj_settings; then
    echo "  Project-scope ($PROJECT_DIR):"
    $has_proj_rules    && echo "    📐 Project rules found"
    $has_proj_settings && echo "    ⚙️  Project settings found"
  fi
  if [ ${#warnings[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Warnings (non-blocking):"
    for w in "${warnings[@]}"; do
      echo "    - $w"
    done
  fi
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
