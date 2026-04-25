#!/usr/bin/env python3
"""Decision memory across audit runs.

Persists the user's decisions from each audit so the next run can surface only
deltas — items new since last audit, items whose evidence has changed,
snoozed items now due — instead of asking about everything from zero.

Storage: ~/.claude/.audit-history/<ISO-timestamp>.json. One file per audit.
The newest file is the "previous audit" the next run reads.

Usage:
    audit-history.py save <audit-type> <markdown-path>
        Parse the user's pasted-back markdown export, extract the JSON envelope,
        and write a history entry. <audit-type> is "skills" or "rules".

    audit-history.py latest [<audit-type>]
        Print the latest history entry as JSON, optionally filtered by type.
        Empty stdout if no history.

    audit-history.py diff <audit-type> <current-items.json>
        Compare current item ids against the latest audit. Print three groups:
        new (in current, not in previous), gone (in previous, not in current),
        and changed (where evidence differs).

The JSON envelope embedded in the markdown export looks like:
    <!-- claude-config-audit:decisions
    { "auditType": "skills", "generatedAt": "...", "decisions": {...} }
    -->
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
HISTORY_DIR = HOME / ".claude" / ".audit-history"

ENVELOPE_RE = re.compile(
    r"<!--\s*claude-config-audit:decisions\s*\n(.*?)\n\s*-->",
    re.DOTALL,
)


def usage() -> None:
    print(__doc__, file=sys.stderr)


def parse_envelope(markdown: str) -> dict | None:
    """Extract the JSON envelope from the HTML's markdown export. None if not found."""
    m = ENVELOPE_RE.search(markdown)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return None


def cmd_save(audit_type: str, markdown_path: str) -> int:
    if audit_type not in ("skills", "rules"):
        print(f"audit-type must be 'skills' or 'rules', got: {audit_type}", file=sys.stderr)
        return 2

    text = Path(markdown_path).read_text(encoding="utf-8")
    envelope = parse_envelope(text)
    if envelope is None:
        print("no decisions envelope found in markdown — nothing to save", file=sys.stderr)
        return 1

    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H-%M-%S")
    out = HISTORY_DIR / f"{timestamp}--{audit_type}.json"
    out.write_text(json.dumps(envelope, indent=2), encoding="utf-8")
    print(out)
    return 0


def latest_history(audit_type: str | None = None) -> Path | None:
    if not HISTORY_DIR.exists():
        return None
    pattern = f"*--{audit_type}.json" if audit_type else "*.json"
    files = sorted(HISTORY_DIR.glob(pattern))
    return files[-1] if files else None


def cmd_latest(audit_type: str | None = None) -> int:
    p = latest_history(audit_type)
    if p is None:
        return 0  # silent — no history yet
    print(p.read_text(encoding="utf-8"))
    return 0


def cmd_diff(audit_type: str, current_path: str) -> int:
    if audit_type not in ("skills", "rules"):
        print(f"audit-type must be 'skills' or 'rules'", file=sys.stderr)
        return 2

    current_raw = Path(current_path).read_text(encoding="utf-8")
    current = json.loads(current_raw)
    # Accept either { items: [...] } or a bare list of {id, ...} dicts.
    if isinstance(current, dict) and "items" in current:
        current_items = current["items"]
    elif isinstance(current, list):
        current_items = current
    else:
        print("current items file must be a list or {items: [...]}", file=sys.stderr)
        return 2

    current_ids = {it["id"]: it for it in current_items if "id" in it}

    previous_path = latest_history(audit_type)
    if previous_path is None:
        # First run — everything is new.
        result = {
            "previous": None,
            "new": list(current_ids.keys()),
            "gone": [],
            "changed": [],
        }
        print(json.dumps(result, indent=2))
        return 0

    previous = json.loads(previous_path.read_text(encoding="utf-8"))
    previous_decisions = previous.get("decisions", {})

    new = [iid for iid in current_ids if iid not in previous_decisions]
    gone = [iid for iid in previous_decisions if iid not in current_ids]
    changed = []
    for iid, item in current_ids.items():
        prev = previous_decisions.get(iid)
        if not prev:
            continue
        # Detect evidence change — invocations going from "0 in 90d" to "5 in 90d"
        # is a strong signal to re-evaluate. Note: this is best-effort — the
        # data shape varies between skills and rules, so we compare what's
        # comparable.
        prev_invocations = prev.get("invocations")
        curr_invocations = item.get("invocations")
        if prev_invocations and curr_invocations and prev_invocations != curr_invocations:
            changed.append({
                "id": iid,
                "previousDecision": prev.get("decision"),
                "previousInvocations": prev_invocations,
                "currentInvocations": curr_invocations,
                "previousNote": prev.get("note", ""),
            })

    result = {
        "previous": str(previous_path),
        "previousAuditAt": previous.get("generatedAt"),
        "new": new,
        "gone": gone,
        "changed": changed,
    }
    print(json.dumps(result, indent=2))
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        usage()
        return 2

    cmd = argv[1]
    if cmd == "save":
        if len(argv) < 4:
            usage()
            return 2
        return cmd_save(argv[2], argv[3])
    if cmd == "latest":
        return cmd_latest(argv[2] if len(argv) >= 3 else None)
    if cmd == "diff":
        if len(argv) < 4:
            usage()
            return 2
        return cmd_diff(argv[2], argv[3])

    usage()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
