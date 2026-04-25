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
