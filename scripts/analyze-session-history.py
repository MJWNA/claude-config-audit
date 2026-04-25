#!/usr/bin/env python3
"""Deterministic invocation counter for Claude Code session history.

The skills audit needs to know how often each plugin / skill / slash command
fires, broken down by date. Asking an LLM agent to count by greppping JSONL
is unreliable — agents sample and summarize, occasionally invent counts.

This script does the boring half deterministically. It walks
`~/.claude/projects/**/*.jsonl`, extracts three classes of evidence, and
emits a JSON document the agents can interpret instead of recompute:

  { "windowDays": 90,
    "scannedAt":  "2026-04-25T22:00:00Z",
    "filesScanned": 134,
    "skills": {
      "<skill-name>": { "count": 12, "lastSeen": "2026-04-22T10:30:00Z",
                        "firstSeen": "2026-03-12T08:01:00Z",
                        "byDay": {"2026-04-22": 3, ...} }, ... },
    "slashCommands": {
      "<command-name>": { "count": 5, "lastSeen": "...", "firstSeen": "...",
                          "byDay": {...} }, ... },
    "bashPatterns": {
      "<pattern-label>": { "count": 7, "lastSeen": "...", "firstSeen": "...",
                           "byDay": {...} }, ... }
  }

The signals counted (only what the user actually invoked):

  1. **Skill tool calls** — assistant tool_use blocks where `name == "Skill"`
     and `input.skill == "<name>"`. This is the canonical "skill ran" event.

  2. **Slash commands** — user message content containing
     `<command-name>/<command></command-name>` tags (Claude Code's serialised
     form of a typed `/<command>`). De-duped within a session: one user
     invocation = one count, even if the tag appears in multiple records.

  3. **Bash patterns** — passed via `--bash-pattern <label>=<regex>` (repeatable).
     Counts tool_use blocks where `name == "Bash"` and `input.command` matches
     the regex. Used to attribute bare CLI invocations of plugin scripts to
     their owning plugin.

Anti-patterns this script deliberately ignores (they were the false-positive
sources in v1's agent-only counting):

  • Skill descriptions appearing in `<system-reminder>` registry blocks. Those
    text snippets show every available skill on every session start; counting
    them would give every installed skill a full sweep of activity.
  • Skill names mentioned inside agent tool prompts or in user messages. A
    plan describing what to do is not the same as actually doing it.
  • Loose substring matches against tool-use input — only structured
    `name == "Skill"` and `input.skill == "<name>"` count.

Usage:
    analyze-session-history.py [--projects-dir <path>] [--window-days 90]
                               [--bash-pattern <label>=<regex> ...]
                               [--out <path> | -]

If --out is omitted (or `-`), the JSON is written to stdout.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

DEFAULT_PROJECTS_DIR = Path.home() / ".claude" / "projects"

# Slash command tag in user messages — Claude Code wraps typed slash commands
# in this exact tag. The capture group is the command name (may contain `:`
# for plugin-namespaced commands, e.g. `vercel:deploy`).
SLASH_RE = re.compile(r"<command-name>/?([\w:-]+)</command-name>")


def parse_iso(ts: str | None) -> datetime | None:
    """Parse an ISO timestamp; return None on anything we can't read.

    Session JSONL records use a few shapes — we accept all of them and bail
    quietly on anything else (better to skip a record than crash the run).
    """
    if not ts or not isinstance(ts, str):
        return None
    try:
        # 2026-04-22T10:30:00.000Z and 2026-04-22T10:30:00+00:00 both work.
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def update_counter(table: dict, key: str, when: datetime | None) -> None:
    """Bump the counter for `key`, recording first/last/byDay. Ignores when=None."""
    if not key:
        return
    entry = table.setdefault(key, {"count": 0, "firstSeen": None, "lastSeen": None, "byDay": {}})
    entry["count"] += 1
    if when is not None:
        iso = when.isoformat()
        if not entry["firstSeen"] or iso < entry["firstSeen"]:
            entry["firstSeen"] = iso
        if not entry["lastSeen"] or iso > entry["lastSeen"]:
            entry["lastSeen"] = iso
        day = iso[:10]
        entry["byDay"][day] = entry["byDay"].get(day, 0) + 1


def iter_records(jsonl_path: Path):
    """Yield parsed JSON records from a JSONL file. Skips malformed lines."""
    try:
        with jsonl_path.open(encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
    except OSError:
        return


def extract_message_content(record: dict) -> tuple[str, list, datetime | None]:
    """Return (role, content_blocks, timestamp) from a session record.

    Session records vary slightly between Claude Code versions — sometimes the
    message is at the top level, sometimes nested under `message`. We accept
    both. content_blocks is always a list (a string content gets wrapped).
    """
    when = parse_iso(record.get("timestamp")) or parse_iso(record.get("ts"))
    msg = record.get("message")
    if isinstance(msg, dict):
        role = msg.get("role", "")
        content = msg.get("content", [])
    else:
        role = record.get("role", "")
        content = record.get("content", [])

    if isinstance(content, str):
        content_blocks = [{"type": "text", "text": content}]
    elif isinstance(content, list):
        content_blocks = content
    else:
        content_blocks = []

    return role, content_blocks, when


def scan_file(
    path: Path,
    cutoff: datetime | None,
    skills: dict,
    slash_commands: dict,
    bash_patterns: list[tuple[str, re.Pattern]],
    bash_counters: dict,
) -> int:
    """Scan one JSONL file. Returns 1 if any record fell within the window."""
    seen_slash_in_session: set[str] = set()
    in_window = False
    for record in iter_records(path):
        role, blocks, when = extract_message_content(record)
        if cutoff and when and when < cutoff:
            continue
        in_window = True

        for block in blocks:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")

            if btype == "tool_use":
                tool_name = block.get("name")
                tool_input = block.get("input") or {}
                if tool_name == "Skill":
                    skill_name = tool_input.get("skill")
                    if isinstance(skill_name, str):
                        update_counter(skills, skill_name, when)
                elif tool_name == "Bash":
                    cmd = tool_input.get("command") or ""
                    if isinstance(cmd, str):
                        for label, pat in bash_patterns:
                            if pat.search(cmd):
                                update_counter(bash_counters, label, when)

            elif btype == "text" and role == "user":
                txt = block.get("text") or ""
                if isinstance(txt, str) and "<command-name>" in txt:
                    for match in SLASH_RE.finditer(txt):
                        cmd_name = match.group(1)
                        # Dedupe: a single user turn usually contains the slash
                        # command tag once; if it appears multiple times in
                        # the same record, count once. Across records in the
                        # same session, count each occurrence (the user typed
                        # it again).
                        sig = f"{record.get('uuid', id(record))}:{cmd_name}"
                        if sig in seen_slash_in_session:
                            continue
                        seen_slash_in_session.add(sig)
                        update_counter(slash_commands, cmd_name, when)
    return 1 if in_window else 0


def parse_bash_pattern(spec: str) -> tuple[str, re.Pattern]:
    """Split `label=regex` into (label, compiled regex). Raises ValueError."""
    if "=" not in spec:
        raise ValueError(f"--bash-pattern must be label=regex, got: {spec!r}")
    label, regex = spec.split("=", 1)
    label = label.strip()
    regex = regex.strip()
    if not label or not regex:
        raise ValueError(f"--bash-pattern must have non-empty label and regex: {spec!r}")
    return label, re.compile(regex)


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument(
        "--projects-dir",
        default=str(DEFAULT_PROJECTS_DIR),
        help=f"Path to ~/.claude/projects (default: {DEFAULT_PROJECTS_DIR})",
    )
    p.add_argument(
        "--window-days",
        type=int,
        default=90,
        help="Restrict counts to the last N days (default 90; 0 = unlimited)",
    )
    p.add_argument(
        "--bash-pattern",
        action="append",
        default=[],
        help="label=regex; count tool_use Bash commands matching the regex. Repeatable.",
    )
    p.add_argument(
        "--out",
        "-o",
        default="-",
        help="Write JSON to this path (default: stdout)",
    )
    args = p.parse_args(argv)

    projects = Path(args.projects_dir).expanduser()
    if not projects.exists():
        print(f"projects dir not found: {projects}", file=sys.stderr)
        return 0  # silent — first-run installs have no session history yet

    cutoff: datetime | None = None
    if args.window_days > 0:
        cutoff = datetime.now(tz=timezone.utc) - timedelta(days=args.window_days)

    try:
        bash_patterns = [parse_bash_pattern(spec) for spec in args.bash_pattern]
    except (ValueError, re.error) as e:
        print(f"bad --bash-pattern: {e}", file=sys.stderr)
        return 2

    skills: dict = {}
    slash_commands: dict = {}
    bash_counters: dict = {}

    files_scanned = 0
    for jsonl_path in sorted(projects.rglob("*.jsonl")):
        files_scanned += scan_file(
            jsonl_path, cutoff, skills, slash_commands, bash_patterns, bash_counters
        )

    output = {
        "windowDays": args.window_days,
        "scannedAt": datetime.now(tz=timezone.utc).isoformat(),
        "filesScanned": files_scanned,
        "projectsDir": str(projects),
        "skills": skills,
        "slashCommands": slash_commands,
        "bashPatterns": bash_counters,
    }

    payload = json.dumps(output, indent=2, sort_keys=True)
    if args.out in ("-", ""):
        sys.stdout.write(payload + "\n")
    else:
        Path(args.out).write_text(payload, encoding="utf-8")
        print(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
