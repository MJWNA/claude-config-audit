"""Tests for .claude-plugin/marketplace.json shape.

Why this lives in CI: in v2.3 we shipped a marketplace.json that failed
`claude plugin validate .` with two errors — root-level `description`
(unrecognized) and `plugins[0].source = "."` (invalid input). The plugin
install path was broken between v2.3.0 and v2.3.1. CI didn't catch it because
no test asserted the manifest shape.

These tests assert the shape we actually need without requiring the claude
CLI to be installed in CI. The claude binary IS the source of truth for
validation, but a Python-only shape check catches the most common
regressions (root-level description coming back, source pointing at "."
instead of "./", marketplace name drifting from plugin name) and runs in
~50ms with zero install footprint.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
MANIFEST = REPO_ROOT / ".claude-plugin" / "marketplace.json"
PLUGIN_JSON = REPO_ROOT / ".claude-plugin" / "plugin.json"


class TestMarketplaceManifest(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(MANIFEST.is_file(), f"missing {MANIFEST}")
        self.data = json.loads(MANIFEST.read_text(encoding="utf-8"))

    def test_no_root_level_description(self):
        # The marketplace schema doesn't accept a root `description` field.
        # `claude plugin validate` rejects it with `root: Unrecognized key:
        # "description"`. Marketplace description belongs under `metadata`.
        self.assertNotIn("description", self.data,
            "root-level `description` is unrecognized — move it to metadata.description")

    def test_metadata_holds_marketplace_description(self):
        meta = self.data.get("metadata", {})
        self.assertIsInstance(meta, dict, "metadata must be an object")
        self.assertIn("description", meta,
            "marketplace description belongs under metadata.description")

    def test_required_top_level_fields(self):
        for field in ("name", "owner", "plugins"):
            self.assertIn(field, self.data, f"missing required field {field!r}")

    def test_owner_shape(self):
        owner = self.data.get("owner")
        self.assertIsInstance(owner, dict)
        self.assertIn("name", owner)

    def test_plugins_is_non_empty_list(self):
        plugins = self.data.get("plugins")
        self.assertIsInstance(plugins, list)
        self.assertGreater(len(plugins), 0, "marketplace must declare at least one plugin")

    def test_plugin_source_not_dot(self):
        # `claude plugin validate` rejects `"source": "."` with `Invalid
        # input`. Relative paths must be `./` or a deeper subpath. A bare dot
        # is a v2.3.0 regression we never want to ship again.
        for i, plugin in enumerate(self.data["plugins"]):
            src = plugin.get("source")
            self.assertNotEqual(src, ".",
                f'plugins[{i}].source = "." is invalid — use "./" instead')

    def test_plugin_source_present_and_string(self):
        for i, plugin in enumerate(self.data["plugins"]):
            self.assertIn("source", plugin, f"plugins[{i}] missing source")
            self.assertIsInstance(plugin["source"], (str, dict),
                f"plugins[{i}].source must be a string path or a {{type, repo}} object")

    def test_plugin_name_matches_plugin_json(self):
        # If marketplace.plugin[0].name diverges from .claude-plugin/plugin.json
        # name, the install command `<plugin>@<marketplace>` becomes ambiguous.
        plugin_json = json.loads(PLUGIN_JSON.read_text(encoding="utf-8"))
        marketplace_first = self.data["plugins"][0]
        self.assertEqual(marketplace_first["name"], plugin_json["name"],
            "plugin name in marketplace.json must match plugin.json")

    def test_plugin_versions_aligned(self):
        # plugin.json wins at install time per Claude Code's
        # calculatePluginVersion precedence. Keep them in sync so the
        # marketplace listing doesn't lie about the version.
        plugin_json = json.loads(PLUGIN_JSON.read_text(encoding="utf-8"))
        marketplace_first = self.data["plugins"][0]
        self.assertEqual(marketplace_first.get("version"), plugin_json.get("version"),
            "marketplace.plugins[0].version must match plugin.json version")


class TestPluginManifest(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(PLUGIN_JSON.is_file(), f"missing {PLUGIN_JSON}")
        self.data = json.loads(PLUGIN_JSON.read_text(encoding="utf-8"))

    def test_required_fields(self):
        for field in ("name", "version", "description"):
            self.assertIn(field, self.data, f"plugin.json missing required field {field!r}")

    def test_version_is_semver_shape(self):
        v = self.data.get("version", "")
        parts = v.split(".")
        self.assertEqual(len(parts), 3, f"version {v!r} should be MAJOR.MINOR.PATCH")
        for p in parts:
            self.assertTrue(p.isdigit(), f"version part {p!r} must be numeric")


if __name__ == "__main__":
    unittest.main()
