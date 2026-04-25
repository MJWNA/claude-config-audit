"""Tests for scripts/inject-audit-data.py — the HTML data injector.

These run under any Python ≥ 3.9. No third-party deps.

The script's correctness has two parts:
  • Splice fidelity — the JSON we put in is the JSON we get back.
  • Escape safety — agent output containing `</script>`, U+2028, etc cannot
    break the script tag or the JS parse.

We test both with adversarial payloads and against the real templates shipped
in `assets/`.
"""

from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "inject-audit-data.py"


def load_inject_module():
    """Import the script as a module (it has a hyphen so we can't `import` it)."""
    spec = importlib.util.spec_from_file_location("inject_audit_data", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestSafeJsonForScript(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_inject_module()

    def test_escapes_close_script_tag(self):
        out = self.mod.safe_json_for_script(["</script>"])
        self.assertNotIn("</script>", out)
        self.assertNotIn("</", out)


class TestSecretRedaction(unittest.TestCase):
    """v2.3 added a defence-in-depth secret scrubber to safe_json_for_script.

    The security-pass agent prompt asks for fingerprinted evidence (e.g.
    `OPENAI_API_KEY=***[redacted, 132 chars]`), but a misbehaving agent
    might still paste the raw value into the `evidence`/`why`/`fix` fields.
    Without this layer, raw secrets would land in the rendered HTML, the
    markdown export, and the audit-history file. These tests assert the
    scrubber catches the formats most likely to be misembedded.
    """

    def setUp(self) -> None:
        self.mod = load_inject_module()

    # Fixtures are built up by string concatenation so the source file
    # itself doesn't contain a literal that matches GitHub's secret-scanning
    # patterns. The runtime values are still complete enough to exercise
    # _redact_string correctly.
    def _fake_secret(self, prefix: str, body_len: int = 24) -> str:
        # Body is a deterministic non-secret pattern; "x"*body_len is a
        # legitimate secret-shape but contains no real entropy.
        return prefix + ("x" * body_len)

    def test_openai_sk_proj_key_redacted(self):
        secret = self._fake_secret("sk" + "-proj-")
        s = f"evidence: OPENAI_API_KEY={secret}"
        out = self.mod._redact_string(s)
        self.assertIn("sk-proj-***[redacted", out)
        self.assertNotIn("xxxxxxxxxxxxxxxxxxxxxxxx", out)

    def test_github_pat_redacted(self):
        secret = self._fake_secret("ghp" + "_", body_len=36)
        s = f"GITHUB_TOKEN={secret}"
        out = self.mod._redact_string(s)
        self.assertIn("ghp_***[redacted", out)

    def test_slack_bot_token_redacted(self):
        # Avoid a literal `xoxb-...` in source — split prefix + assembled body
        # so secret scanners don't pattern-match against this test fixture.
        prefix = "xo" + "xb-"
        body = "1234567890-" + ("a" * 20)
        s = f"Slack: {prefix}{body}"
        out = self.mod._redact_string(s)
        self.assertIn("xoxb-***[redacted", out)

    def test_google_api_key_redacted(self):
        prefix = "AI" + "za"
        body = "B" * 35
        s = f"{prefix}{body}"
        out = self.mod._redact_string(s)
        self.assertIn("AIza***[redacted", out)

    def test_generic_password_assignment_redacted(self):
        s = "PASSWORD=hunter2isnotenoughchars"
        out = self.mod._redact_string(s)
        self.assertIn("PASSWORD=***[redacted", out)

    def test_innocuous_text_unchanged(self):
        s = "this skill has not been invoked in the last 90 days"
        self.assertEqual(self.mod._redact_string(s), s)

    def test_redaction_is_idempotent(self):
        # Re-running the scrubber on already-redacted text must not produce
        # `[redacted, [redacted, N chars]` etc.
        s = "key=***[redacted, 24 chars]"
        self.assertEqual(self.mod._redact_string(s), s)

    def test_secrets_redacted_through_inject_pipeline(self):
        # End-to-end: a secret inside an audit-data string lands in the
        # rendered HTML as a redaction marker, not as the literal value.
        # Build the secret-shape from parts so secret scanners don't
        # pattern-match against the test source.
        secret = "sk" + "-proj-" + ("a" * 20)
        payload = {"securityFindings": [{
            "id": "sf-1",
            "severity": "high",
            "title": "OpenAI key in settings.json",
            "evidence": f"OPENAI_API_KEY={secret}",
            "why": "x", "fix": "y", "verdict": "fix",
        }], "sections": []}
        out = self.mod.safe_json_for_script(payload)
        # The fully-assembled secret string must not appear in output.
        self.assertNotIn(secret, out)
        self.assertIn("redacted", out)

    def test_escapes_open_angle_bracket(self):
        out = self.mod.safe_json_for_script(["<img src=x onerror=alert(1)>"])
        self.assertNotIn("<img", out)
        self.assertNotIn("<", out.replace("\\u003c", ""))

    def test_escapes_line_separator(self):
        out = self.mod.safe_json_for_script(["a b"])
        self.assertNotIn(" ", out)
        self.assertIn("\\u2028", out)

    def test_escapes_paragraph_separator(self):
        out = self.mod.safe_json_for_script(["a b"])
        self.assertNotIn(" ", out)
        self.assertIn("\\u2029", out)

    def test_roundtrip_preserves_data(self):
        payload = [
            {"name": "evil", "desc": "</script><script>alert(1)</script>"},
            {"name": "u2028", "desc": "line1 line2"},
            {"name": "quotes", "desc": 'with "embedded" quotes'},
            {"name": "nested", "items": [1, 2, {"k": "v"}]},
        ]
        out = self.mod.safe_json_for_script(payload)
        recovered = json.loads(out)
        self.assertEqual(recovered, payload)


class TestFindInjectionSpan(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_inject_module()

    def test_finds_array_placeholder(self):
        tmpl = "x /* AUDIT_DATA_INJECTION_POINT */ [] y"
        start, end = self.mod.find_injection_span(tmpl)
        self.assertEqual(tmpl[start:end], "/* AUDIT_DATA_INJECTION_POINT */ []")

    def test_finds_object_placeholder(self):
        tmpl = "x /* AUDIT_DATA_INJECTION_POINT */ {} y"
        start, end = self.mod.find_injection_span(tmpl)
        self.assertEqual(tmpl[start:end], "/* AUDIT_DATA_INJECTION_POINT */ {}")

    def test_handles_nested_array(self):
        tmpl = "/* AUDIT_DATA_INJECTION_POINT */ [[1, 2], [3, 4]]"
        start, end = self.mod.find_injection_span(tmpl)
        self.assertEqual(tmpl[start:end].split(" */ ")[1], "[[1, 2], [3, 4]]")

    def test_handles_nested_object(self):
        tmpl = '/* AUDIT_DATA_INJECTION_POINT */ {"a": {"b": [1, 2]}}'
        start, end = self.mod.find_injection_span(tmpl)
        self.assertEqual(tmpl[start:end].split(" */ ")[1], '{"a": {"b": [1, 2]}}')

    def test_skips_brackets_inside_strings(self):
        tmpl = '/* AUDIT_DATA_INJECTION_POINT */ ["a]b", "c[d"]'
        start, end = self.mod.find_injection_span(tmpl)
        self.assertEqual(tmpl[start:end].split(" */ ")[1], '["a]b", "c[d"]')

    def test_missing_marker_raises(self):
        with self.assertRaises(ValueError):
            self.mod.find_injection_span("no marker here")

    def test_marker_followed_by_garbage_raises(self):
        with self.assertRaises(ValueError):
            self.mod.find_injection_span("/* AUDIT_DATA_INJECTION_POINT */ xyz")


class TestRealTemplates(unittest.TestCase):
    """End-to-end injection against the real template files."""

    def _run_inject(self, template: Path, payload) -> Path:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as t:
            json.dump(payload, t)
            data_path = t.name
        out_path = tempfile.mktemp(suffix=".html")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(template), data_path, "-o", out_path],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        return Path(out_path)

    def _assert_no_breakout(self, html: str) -> None:
        for body in re.findall(r"<script>(.*?)</script>", html, re.DOTALL):
            self.assertNotIn("</script", body, "</script breakout in injected JS body")
            self.assertNotIn(" ", body, "raw U+2028 in JS body")
            self.assertNotIn(" ", body, "raw U+2029 in JS body")

    def test_skills_template_with_adversarial_payload(self):
        template = REPO_ROOT / "assets" / "skills-audit-template.html"
        payload = {
            "sections": [{"section": "📦 Test", "items": [{
                "id": "p-evil", "name": "</script><script>alert(1)</script>",
                "type": "plugin", "verdict": "delete", "confidence": "high",
                "invocations": "0 in 90d", "mostRecent": "Never",
                "desc": "line line", "triggers": "para para",
                "evidence": "</script", "agentReason": "x",
            }]}],
            "securityFindings": [{
                "id": "sf-test", "severity": "high", "category": "test",
                "title": "Test finding", "evidence": "</script>",
                "why": "x", "fix": "y", "verdict": "fix",
            }],
        }
        out = self._run_inject(template, payload)
        html = out.read_text()
        self._assert_no_breakout(html)
        self.assertIn("renderSecurityFindings", html)

    def test_rules_template_with_adversarial_payload(self):
        template = REPO_ROOT / "assets" / "rules-audit-template.html"
        payload = {
            "existingRules": [{
                "id": "r-evil", "name": "</script>.md", "verdict": "keep",
                "confidence": "high", "sizeLines": 1, "sizeKB": "0.1KB",
                "currentFM": "none", "actualLoad": "always",
                "declaredLoad": "always", "match": True,
                "whatItDoes": "x y", "whenItFires": "x", "whyItExists": "x",
                "withoutThisRule": "x", "quality": "x", "issues": "x",
                "actionItems": [], "agentReason": "x",
            }],
            "mismatches": [], "newRules": [], "extensions": [], "refreshes": {},
            "securityFindings": [{
                "id": "sf-r-test", "severity": "medium", "category": "stale-ref",
                "title": "Stale reference",
                "evidence": "references </script>",
                "why": "x", "fix": "y", "verdict": "ack",
            }],
        }
        out = self._run_inject(template, payload)
        html = out.read_text()
        self._assert_no_breakout(html)
        self.assertIn("renderSecurityFindings", html)


if __name__ == "__main__":
    unittest.main()
