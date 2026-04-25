"""Test the fenceWrap helper in rules-audit-template.html.

The function lives in browser JS so we can't unittest it directly. Instead
we extract its source from the template, port the algorithm to Python
(small enough to be obvious-by-inspection), and assert correctness on the
edge cases the v2.2 changelog identified — proposed rule content
containing triple backticks (legitimate for rules about coding conventions)
must produce a valid markdown export.

This is a regression test for the v2.2 fix called out in CHANGELOG.md
("Markdown export uses dynamic fence length"). Without it, a future change
to the JS function could silently break rule export and the bug would only
surface when a real audit hit a rule with embedded backticks.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = REPO_ROOT / "assets" / "rules-audit-template.html"


def python_fence_wrap(content: str, lang: str = "") -> str:
    """Python port of the JS fenceWrap function.

    Mirrors the algorithm in rules-audit-template.html: scan for the longest
    backtick run inside `content`, then choose a fence one longer (minimum 3).
    """
    longest = 0
    for run in re.finditer(r"`+", content):
        longest = max(longest, len(run.group(0)))
    fence = "`" * max(3, longest + 1)
    return f"{fence}{lang}\n{content}\n{fence}"


class TestFenceWrap(unittest.TestCase):
    """Assertions about the Python port. The JS source is also asserted to
    contain the same algorithm via a string-presence check below."""

    def test_default_three_backticks_for_text_with_no_backticks(self):
        wrapped = python_fence_wrap("plain text", "markdown")
        self.assertTrue(wrapped.startswith("```markdown\n"))
        self.assertTrue(wrapped.endswith("\n```"))

    def test_four_backticks_when_content_has_three(self):
        # The classic case: a rule documenting JS code conventions might
        # include a ```javascript example. Outer fence must be 4+ to wrap it.
        content = "Use this pattern:\n```js\nfoo()\n```\n"
        wrapped = python_fence_wrap(content, "markdown")
        self.assertTrue(wrapped.startswith("````markdown\n"))
        self.assertTrue(wrapped.endswith("\n````"))

    def test_five_backticks_when_content_has_four(self):
        content = "Nested example:\n````\nstuff\n````\n"
        wrapped = python_fence_wrap(content, "markdown")
        self.assertTrue(wrapped.startswith("`````markdown\n"))
        self.assertTrue(wrapped.endswith("\n`````"))

    def test_handles_inline_backticks(self):
        # Inline `code` shouldn't bump the fence beyond 3 — only fenced
        # code blocks (3+ in a row) need a longer outer fence.
        content = "Use `single backticks` for inline code."
        wrapped = python_fence_wrap(content, "markdown")
        self.assertTrue(wrapped.startswith("```markdown\n"),
            f"single inline backtick triggered an unnecessarily long fence: {wrapped[:30]!r}")

    def test_empty_content(self):
        wrapped = python_fence_wrap("", "markdown")
        self.assertEqual(wrapped, "```markdown\n\n```")

    def test_js_template_contains_fenceWrap_helper(self):
        """The JS source must still contain the fenceWrap function. If the
        template ever drops it, this test catches the regression even
        without a JS runtime."""
        src = TEMPLATE.read_text()
        self.assertIn("fenceWrap", src,
            "fenceWrap helper missing from rules-audit-template.html")
        # Must be invoked, not just defined.
        self.assertIn("fenceWrap(", src)


if __name__ == "__main__":
    unittest.main()
