#!/usr/bin/env bash
# Inventory the current Claude Code installation.
# Outputs a structured summary that the skill consumes to build agent prompts.

set -u

CLAUDE_DIR="$HOME/.claude"

echo "=== Claude Code config discovery ==="
echo ""

# === Plugins ===
echo "## Plugins (from installed_plugins.json)"
if [ -f "$CLAUDE_DIR/plugins/installed_plugins.json" ]; then
  python3 -c "
import json, sys
with open('$CLAUDE_DIR/plugins/installed_plugins.json') as f:
    d = json.load(f)
plugins = d.get('plugins', {})
print(f'Total: {len(plugins)}')
print()
for key in sorted(plugins.keys()):
    entries = plugins[key]
    if entries:
        e = entries[0]
        print(f'  - {key} (v{e.get(\"version\", \"?\")}, installed {e.get(\"installedAt\", \"?\")[:10]})')
"
else
  echo "  (no installed_plugins.json found)"
fi
echo ""

# === Standalone skills ===
echo "## Standalone skills (~/.claude/skills/)"
if [ -d "$CLAUDE_DIR/skills" ]; then
  count=$(ls -1 "$CLAUDE_DIR/skills" 2>/dev/null | wc -l | tr -d ' ')
  echo "Total: $count"
  echo ""
  for skill in $(ls -1 "$CLAUDE_DIR/skills" 2>/dev/null); do
    skill_md="$CLAUDE_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_md" ]; then
      desc=$(grep -m1 "^description:" "$skill_md" 2>/dev/null | sed 's/description: //;s/^["'"'"']//;s/["'"'"']$//' | head -c 100)
      echo "  - $skill — $desc"
    else
      echo "  - $skill (no SKILL.md)"
    fi
  done
else
  echo "  (no ~/.claude/skills/ directory)"
fi
echo ""

# === User-scope rules ===
echo "## User-scope rules (~/.claude/rules/)"
if [ -d "$CLAUDE_DIR/rules" ]; then
  count=$(ls -1 "$CLAUDE_DIR/rules" 2>/dev/null | wc -l | tr -d ' ')
  echo "Total: $count"
  echo ""
  for rule in $(ls -1 "$CLAUDE_DIR/rules" 2>/dev/null); do
    rule_path="$CLAUDE_DIR/rules/$rule"
    [ -f "$rule_path" ] || continue
    lines=$(wc -l < "$rule_path" | tr -d ' ')
    bytes=$(wc -c < "$rule_path" | tr -d ' ')
    has_fm="no"
    [ "$(head -1 "$rule_path" 2>/dev/null)" = "---" ] && has_fm="yes"
    echo "  - $rule ($lines lines, $bytes bytes, frontmatter: $has_fm)"
  done
else
  echo "  (no ~/.claude/rules/ directory)"
fi
echo ""

# === Session history depth ===
echo "## Session history"
if [ -d "$CLAUDE_DIR/projects" ]; then
  total_sessions=$(find "$CLAUDE_DIR/projects" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  echo "Total Claude Code session files: $total_sessions"
  if [ "$total_sessions" -gt 0 ]; then
    oldest=$(find "$CLAUDE_DIR/projects" -name "*.jsonl" -exec stat -f "%m %N" {} \; 2>/dev/null | sort -n | head -1 | awk '{print $1}')
    if [ -n "$oldest" ]; then
      oldest_date=$(date -r "$oldest" "+%Y-%m-%d" 2>/dev/null || echo "?")
      echo "Oldest session: $oldest_date"
    fi
  fi
else
  echo "  (no ~/.claude/projects/ — limited session-history evidence)"
fi
echo ""

echo "=== Discovery complete ==="
