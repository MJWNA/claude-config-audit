"""Tests for scripts/analyze-session-history.py — the deterministic counter.

Builds a synthetic projects directory with hand-rolled JSONL records, runs the
analyzer against it, and checks the counts the analyzer reports match what we
put in. Because the script is the deterministic-counts source of truth, these
tests are the project's contract that "what the script counts" stays stable.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "analyze-session-history.py"


def make_record(role: str, content, when: datetime) -> dict:
    return {
        "type": role,
        "timestamp": when.isoformat().replace("+00:00", "Z"),
        "uuid": f"u-{when.timestamp()}-{role}",
        "message": {"role": role, "content": content},
    }


def write_session(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")


def run_analyzer(projects_dir: Path, *extra_args) -> dict:
    result = subprocess.run(
        [sys.executable, str(SCRIPT),
         "--projects-dir", str(projects_dir), *extra_args],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


class TestCounting(unittest.TestCase):

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.now = datetime.now(tz=timezone.utc)

    def test_counts_skill_tool_calls(self):
        session = self.tmp / "proj-A" / "session1.jsonl"
        records = [
            make_record("assistant", [{
                "type": "tool_use", "name": "Skill", "input": {"skill": "humanizer"}
            }], self.now - timedelta(days=1)),
            make_record("assistant", [{
                "type": "tool_use", "name": "Skill", "input": {"skill": "humanizer"}
            }], self.now - timedelta(days=3)),
            make_record("assistant", [{
                "type": "tool_use", "name": "Skill", "input": {"skill": "ghl-expert"}
            }], self.now - timedelta(days=5)),
        ]
        write_session(session, records)
        out = run_analyzer(self.tmp, "--window-days", "0")
        self.assertEqual(out["skills"]["humanizer"]["count"], 2)
        self.assertEqual(out["skills"]["ghl-expert"]["count"], 1)

    def test_counts_slash_commands(self):
        session = self.tmp / "proj-B" / "session1.jsonl"
        records = [
            make_record(
                "user",
                [{"type": "text", "text": "<command-name>/audit-skills</command-name>"}],
                self.now - timedelta(days=1),
            ),
            make_record(
                "user",
                [{"type": "text", "text": "<command-name>/audit-skills</command-name>"}],
                self.now - timedelta(days=2),
            ),
        ]
        write_session(session, records)
        out = run_analyzer(self.tmp, "--window-days", "0")
        self.assertEqual(out["slashCommands"]["audit-skills"]["count"], 2)

    def test_excludes_records_outside_window(self):
        session = self.tmp / "proj-C" / "session1.jsonl"
        records = [
            make_record("assistant", [{
                "type": "tool_use", "name": "Skill", "input": {"skill": "x"}
            }], self.now - timedelta(days=1)),    # in 30d window
            make_record("assistant", [{
                "type": "tool_use", "name": "Skill", "input": {"skill": "x"}
            }], self.now - timedelta(days=200)),  # outside 30d window
        ]
        write_session(session, records)
        out = run_analyzer(self.tmp, "--window-days", "30")
        # The analyzer compares against `now - 30d`, not against our test's
        # synthetic `now`. So our `1 day ago` record is in window and `200d`
        # is out — which would be true even with real time.
        self.assertEqual(out["skills"]["x"]["count"], 1)

    def test_ignores_skill_names_in_text(self):
        # A user message MENTIONING a skill name shouldn't count it.
        session = self.tmp / "proj-D" / "session1.jsonl"
        records = [
            make_record(
                "user",
                [{"type": "text", "text": "I want to use the humanizer skill"}],
                self.now - timedelta(days=1),
            ),
        ]
        write_session(session, records)
        out = run_analyzer(self.tmp, "--window-days", "0")
        self.assertNotIn("humanizer", out.get("skills", {}))

    def test_bash_pattern_counts(self):
        session = self.tmp / "proj-E" / "session1.jsonl"
        records = [
            make_record("assistant", [{
                "type": "tool_use", "name": "Bash",
                "input": {"command": "bash ~/.claude/skills/foo/scripts/x.sh"}
            }], self.now - timedelta(days=1)),
            make_record("assistant", [{
                "type": "tool_use", "name": "Bash",
                "input": {"command": "bash ~/.claude/skills/foo/scripts/y.sh"}
            }], self.now - timedelta(days=2)),
            make_record("assistant", [{
                "type": "tool_use", "name": "Bash",
                "input": {"command": "ls"}  # should not match
            }], self.now - timedelta(days=3)),
        ]
        write_session(session, records)
        out = run_analyzer(
            self.tmp, "--window-days", "0",
            "--bash-pattern", r"foo-skill=skills/foo/",
        )
        self.assertEqual(out["bashPatterns"]["foo-skill"]["count"], 2)

    def test_handles_malformed_json_lines(self):
        session = self.tmp / "proj-F" / "session1.jsonl"
        session.parent.mkdir(parents=True, exist_ok=True)
        with session.open("w") as f:
            f.write("not json at all\n")
            f.write(json.dumps(make_record(
                "assistant",
                [{"type": "tool_use", "name": "Skill", "input": {"skill": "z"}}],
                self.now - timedelta(days=1),
            )) + "\n")
            f.write("{still not valid\n")
        out = run_analyzer(self.tmp, "--window-days", "0")
        self.assertEqual(out["skills"]["z"]["count"], 1)


if __name__ == "__main__":
    unittest.main()
