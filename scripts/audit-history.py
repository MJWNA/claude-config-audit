#!/usr/bin/env python3
"""Decision memory across audit runs.

Persists the user's decisions from each audit so the next run can surface only
deltas — items new since last audit, items gone since last audit, and items
whose evidence has changed — instead of asking about everything from zero.

Storage: ~/.claude/.audit-history/<ISO-timestamp>.json. One file per audit.
The newest file is the "previous audit" the next run reads.

Usage:
    audit-history.py save <audit-type> <markdown-path>
        Parse the user's pasted-back markdown export, extract the JSON envelope,
        and write a history entry. <audit-type> is "skills" or "rules".
        Refuses to save if the envelope's auditType doesn't match the CLI arg.

    audit-history.py latest [<audit-type>]
        Print the latest history entry as JSON, optionally filtered by type.
        Empty stdout if no history.

    audit-history.py diff <audit-type> <current-items.json>
        Compare current item ids against the latest audit. Print three groups:
        new (in current, not in previous), gone (in previous, not in current),
        and changed (where evidence differs). Refuses to diff against a
        future-schema-version history file.

    audit-history.py purge
        Delete history entries older than CLAUDE_CONFIG_AUDIT_HISTORY_TTL_DAYS
        (default 180). Lets the free-text `note` fields users typed in the
        HTML decision tool age out instead of accumulating forever.

The JSON envelope embedded in the markdown export looks like:
    <!-- claude-config-audit:decisions
    { "schemaVersion": 1, "auditType": "skills",
      "generatedAt": "...", "decisions": {...} }
    -->
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME = Path.home()
HISTORY_DIR = HOME / ".claude" / ".audit-history"

# Decision history is genuinely useful long-term — the whole point is to
# show only deltas vs the last audit. But unbounded retention means
# free-text `note` fields (which can contain whatever the user typed in the
# HTML decision tool) accumulate indefinitely. 180 days is a reasonable
# compromise: enough to span quarterly audit cadences, short enough that
# stale notes age out. Override via env var for users who want longer.
HISTORY_TTL_DAYS = int(os.environ.get("CLAUDE_CONFIG_AUDIT_HISTORY_TTL_DAYS", "180"))

ENVELOPE_RE = re.compile(
    r"<!--\s*claude-config-audit:decisions\s*\n(.*?)\n\s*-->",
    re.DOTALL,
)


def usage() -> None:
    print(__doc__, file=sys.stderr)


class EnvelopeError(ValueError):
    """Raised when the markdown export has no envelope or one that can't be parsed.

    The two failure modes (no envelope vs malformed envelope) are
    semantically different — "you forgot to include the JSON block" needs a
    different recovery action than "the JSON block is corrupted, here is the
    parse error". Earlier versions of `parse_envelope` returned None for
    both, which made `audit-history.py save` print the same message in
    each case. The user couldn't tell whether to re-paste or re-export.
    """


def parse_envelope(markdown: str) -> dict | None:
    """Extract the JSON envelope from the HTML's markdown export.

    Returns None when the marker is absent; raises EnvelopeError when the
    marker is present but the JSON inside fails to parse — that's a
    different operator action (fix the paste vs re-export the audit).
    """
    m = ENVELOPE_RE.search(markdown)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError as e:
        raise EnvelopeError(
            f"envelope marker found but JSON inside is invalid: {e.msg} "
            f"at line {e.lineno} col {e.colno}. Re-export the audit from the HTML."
        ) from e


# Bumped on any breaking change to the envelope shape — `decisions` keys,
# new top-level fields the diff depends on, etc. `cmd_save` writes this
# value into the saved history file; `cmd_diff` reads it and bails clearly
# if the on-disk version doesn't match what this code understands.
ENVELOPE_SCHEMA_VERSION = 1


def cmd_save(audit_type: str, markdown_path: str) -> int:
    if audit_type not in ("skills", "rules"):
        print(
            f"audit-type must be 'skills' or 'rules', got: {audit_type}",
            file=sys.stderr,
        )
        return 2

    md_path = Path(markdown_path)
    if not md_path.is_file():
        print(f"markdown file not found: {markdown_path}", file=sys.stderr)
        return 2
    text = md_path.read_text(encoding="utf-8")

    try:
        envelope = parse_envelope(text)
    except EnvelopeError as e:
        print(str(e), file=sys.stderr)
        return 1

    if envelope is None:
        print(
            "no decisions envelope found in markdown — nothing to save. "
            "The export must end with `<!-- claude-config-audit:decisions ... -->`. "
            "Did you paste the full HTML output including the JSON block?",
            file=sys.stderr,
        )
        return 1

    # Validate the envelope itself matches the audit-type the user asked
    # for. Without this, pasting a rules-export under `save skills` would
    # write the rules envelope as `…--skills.json`; the next `diff skills`
    # would compare current skills against historical *rules* decisions,
    # producing nonsense "new"/"changed" sets. Fail loudly instead.
    embedded_type = envelope.get("auditType")
    if embedded_type and embedded_type != audit_type:
        print(
            f"envelope auditType is {embedded_type!r} but you asked to save "
            f"as {audit_type!r}. This usually means the wrong markdown was "
            "pasted. Re-export the correct audit and try again.",
            file=sys.stderr,
        )
        return 2

    # Stamp the schema version + a unique random suffix on the saved file.
    # The suffix prevents two saves in the same second from overwriting
    # each other (same root cause as the v2.2 quarantine init fix).
    envelope.setdefault("schemaVersion", ENVELOPE_SCHEMA_VERSION)

    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H-%M-%S")
    # Random 6-char suffix using urandom; mirrors quarantine.sh's
    # `mktemp -d "$BASE/$ts-XXXXXX"` pattern.
    import secrets
    nonce = secrets.token_hex(3)  # 6 hex chars
    out = HISTORY_DIR / f"{timestamp}-{nonce}--{audit_type}.json"
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

    cur_path = Path(current_path)
    if not cur_path.is_file():
        print(f"current items file not found: {current_path}", file=sys.stderr)
        return 2
    current_raw = cur_path.read_text(encoding="utf-8")
    try:
        current = json.loads(current_raw)
    except json.JSONDecodeError as e:
        print(
            f"current items file is not valid JSON: {e.msg} at line {e.lineno} col {e.colno}",
            file=sys.stderr,
        )
        return 2
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

    try:
        previous = json.loads(previous_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(
            f"previous history file is corrupted: {previous_path} ({e.msg}). "
            "Move it aside and re-run; the next save will start fresh.",
            file=sys.stderr,
        )
        return 2

    # Refuse to diff against an envelope from a future schema version. A
    # forward-incompatible diff is worse than no diff — `previous_decisions`
    # could miss a field this code doesn't know about. Surface it instead.
    prev_schema = previous.get("schemaVersion", 1)
    if prev_schema > ENVELOPE_SCHEMA_VERSION:
        print(
            f"previous history file uses schemaVersion={prev_schema} but this "
            f"audit-history.py only understands up to {ENVELOPE_SCHEMA_VERSION}. "
            "Either upgrade the skill or move the future-version file aside.",
            file=sys.stderr,
        )
        return 2

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


def cmd_purge() -> int:
    """Delete history entries older than HISTORY_TTL_DAYS.

    Note: history files are useful long-term (delta detection), so the TTL
    is intentionally longer than quarantine's 7 days. The TTL exists so
    free-text `note` fields the user typed in the HTML decision tool age
    out instead of accumulating in `~/.claude/` forever.
    """
    if not HISTORY_DIR.exists():
        return 0
    cutoff = datetime.now(tz=timezone.utc) - timedelta(days=HISTORY_TTL_DAYS)
    purged = 0
    for path in sorted(HISTORY_DIR.glob("*.json")):
        try:
            mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
        except OSError:
            continue
        if mtime < cutoff:
            path.unlink()
            print(f"purged (>{HISTORY_TTL_DAYS}d): {path.name}")
            purged += 1
    print(f"Purged {purged} history file(s)")
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
    if cmd == "purge":
        return cmd_purge()

    usage()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
