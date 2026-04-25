"""Tests for scripts/audit-history.py — the decision-memory store."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "audit-history.py"


def load_history_module():
    spec = importlib.util.spec_from_file_location("audit_history", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestParseEnvelope(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_history_module()

    def test_extracts_envelope(self):
        md = """# Audit
some content
---
<!-- claude-config-audit:decisions
{"auditType": "skills", "generatedAt": "2026-01-01T00:00:00Z",
 "decisions": {"p-foo": {"decision": "delete"}}}
-->
"""
        env = self.mod.parse_envelope(md)
        self.assertIsNotNone(env)
        self.assertEqual(env["auditType"], "skills")
        self.assertIn("p-foo", env["decisions"])

    def test_returns_none_when_no_envelope(self):
        self.assertIsNone(self.mod.parse_envelope("no envelope here"))

    def test_raises_on_invalid_json(self):
        # v2.3 distinguishes "no envelope" (returns None) from "envelope
        # present but JSON inside is malformed" (raises EnvelopeError) so the
        # operator gets a different recovery hint for each case.
        md = """<!-- claude-config-audit:decisions
{ invalid json
-->
"""
        with self.assertRaises(self.mod.EnvelopeError):
            self.mod.parse_envelope(md)


class TestSaveAndLatest(unittest.TestCase):
    """Roundtrip: save a markdown export, then `latest` should print it back."""

    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.env = {**os.environ, "HOME": self.tmp}
        self.mod = load_history_module()

    def _run(self, *args, input_=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            env=self.env,
            input=input_,
            capture_output=True,
            text=True,
        )

    def test_save_then_latest_roundtrip(self):
        md = Path(tempfile.mktemp(suffix=".md"))
        md.write_text("""# Skills audit
---
<!-- claude-config-audit:decisions
{"auditType": "skills", "generatedAt": "2026-01-01T00:00:00Z",
 "summary": {"keep": 1, "delete": 1, "maybe": 0, "undecided": 0},
 "decisions": {
   "p-keep": {"decision": "keep", "agentVerdict": "keep", "invocations": "5 in 90d"},
   "p-del":  {"decision": "delete", "agentVerdict": "delete", "invocations": "0 in 90d"}
 }}
-->
""")
        save_result = self._run("save", "skills", str(md))
        self.assertEqual(save_result.returncode, 0, save_result.stderr)
        self.assertIn(".audit-history", save_result.stdout)

        latest_result = self._run("latest", "skills")
        self.assertEqual(latest_result.returncode, 0, latest_result.stderr)
        latest = json.loads(latest_result.stdout)
        self.assertEqual(latest["auditType"], "skills")
        self.assertIn("p-keep", latest["decisions"])

    def test_save_rejects_invalid_audit_type(self):
        md = Path(tempfile.mktemp(suffix=".md"))
        md.write_text("no envelope")
        result = self._run("save", "garbage", str(md))
        self.assertNotEqual(result.returncode, 0)

    def test_save_rejects_envelope_audit_type_mismatch(self):
        # v2.3 fix: pasting a rules-export under `save skills` would
        # silently write the rules envelope as `…--skills.json`, then the
        # next `diff skills` would compare current skills against
        # historical *rules* decisions. cmd_save now refuses the mismatch.
        md = Path(tempfile.mktemp(suffix=".md"))
        md.write_text("""# Rules audit
---
<!-- claude-config-audit:decisions
{"auditType": "rules", "generatedAt": "2026-01-01", "decisions": {}}
-->
""")
        result = self._run("save", "skills", str(md))
        self.assertEqual(result.returncode, 2,
            f"expected exit 2 on auditType mismatch, got {result.returncode}: {result.stderr}")
        self.assertIn("auditType", result.stderr)

    def test_save_writes_unique_filenames_in_same_second(self):
        # v2.3 fix: random nonce in the saved filename prevents two saves
        # in the same wall-clock second from overwriting each other.
        md = Path(tempfile.mktemp(suffix=".md"))
        md.write_text("""# x
---
<!-- claude-config-audit:decisions
{"auditType": "skills", "generatedAt": "2026-01-01", "decisions": {}}
-->
""")
        paths = set()
        for _ in range(5):
            r = self._run("save", "skills", str(md))
            self.assertEqual(r.returncode, 0, r.stderr)
            paths.add(r.stdout.strip())
        self.assertEqual(len(paths), 5,
            f"expected 5 unique save paths, got {len(paths)}: {paths}")

    def test_save_distinguishes_no_envelope_from_bad_envelope(self):
        # v2.3 split parse_envelope's None return into None vs raise so the
        # operator gets a different recovery hint. cmd_save surfaces the
        # parse error message for malformed JSON.
        bad = Path(tempfile.mktemp(suffix=".md"))
        bad.write_text("""# x
<!-- claude-config-audit:decisions
{ this is not valid json
-->
""")
        result = self._run("save", "skills", str(bad))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid", result.stderr.lower())


class TestDiff(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.env = {**os.environ, "HOME": self.tmp}

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            env=self.env,
            capture_output=True,
            text=True,
        )

    def test_diff_first_run_marks_everything_new(self):
        items = [{"id": "p-a", "invocations": "0"}, {"id": "p-b", "invocations": "5"}]
        items_path = Path(tempfile.mktemp(suffix=".json"))
        items_path.write_text(json.dumps({"items": items}))
        result = self._run("diff", "skills", str(items_path))
        self.assertEqual(result.returncode, 0, result.stderr)
        diff = json.loads(result.stdout)
        self.assertIsNone(diff["previous"])
        self.assertEqual(set(diff["new"]), {"p-a", "p-b"})

    def test_diff_detects_invocation_change(self):
        # Save a prior audit.
        md = Path(tempfile.mktemp(suffix=".md"))
        md.write_text("""# x
---
<!-- claude-config-audit:decisions
{"auditType": "skills", "generatedAt": "2026-01-01",
 "decisions": {"p-a": {"decision": "keep", "invocations": "0 in 90d"}}}
-->
""")
        self._run("save", "skills", str(md))

        # Now feed current items where p-a's invocations have grown.
        items = [{"id": "p-a", "invocations": "12 in 90d"}]
        items_path = Path(tempfile.mktemp(suffix=".json"))
        items_path.write_text(json.dumps(items))
        result = self._run("diff", "skills", str(items_path))
        self.assertEqual(result.returncode, 0, result.stderr)
        diff = json.loads(result.stdout)
        self.assertEqual(len(diff["changed"]), 1)
        self.assertEqual(diff["changed"][0]["id"], "p-a")
        self.assertEqual(diff["changed"][0]["currentInvocations"], "12 in 90d")


if __name__ == "__main__":
    unittest.main()
