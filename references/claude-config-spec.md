# Claude Code Config Spec — Quick Reference

Distilled spec citations for plugins, standalone skills, and rules. Use this as the source of truth when discussing frontmatter, loading behaviour, or what's possible vs not possible.

Last verified against: code.claude.com docs as of 2026-04-25 + GitHub issues #17204, #23478, #13905.

## Three distinct concepts often confused

The Claude Code docs distinguish three things:

| Concept | Where | What | Loading |
|---|---|---|---|
| **CLAUDE.md** | Project root or `~/.claude/CLAUDE.md` | User-written persistent instructions | Always loaded |
| **Auto memory** | `~/.claude/projects/<proj>/memory/MEMORY.md` | Claude-written notes between sessions | Loaded inside the matching project cwd |
| **Rules** | `<project>/.claude/rules/*.md` or `~/.claude/rules/*.md` | User-written conditional instructions | Always-loaded OR path-scoped |

This skill audits **rules** (and plugins/skills, which are different again).

## Rule frontmatter — what's documented

Source: <https://code.claude.com/docs/en/memory#organize-rules-with-claude-rules>

**Frontmatter is OPTIONAL.** A `.md` file with no frontmatter loads unconditionally at session start, with the same priority as `.claude/CLAUDE.md`.

**Only ONE documented field for rules: `paths:`** — a YAML list of glob strings.

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "src/**/*.{ts,tsx}"
---
```

**That's it.** No `name`, `description`, `loading`, `applyTo`, `globs`, or `alwaysApply` field is documented for rules.

### Why your existing rules might have `description:`

Some users (and some Claude versions) write `description:` in rule frontmatter, copying the convention from skills (where description IS used for relevance matching). For rules, the loader silently ignores it. The rule still works — just for a different reason than the user thinks. Cosmetic; not harmful.

If the rule has no `paths`, it loads always by virtue of having no path scoping. The `description` is just decorative documentation.

## Loading modes — only two

1. **Always-loaded** — no frontmatter (or frontmatter without `paths`)
2. **Path-scoped** — `paths:` frontmatter; loads when Claude reads a matching file

There is **no "on-demand" loading mode for rules**. The docs explicitly redirect description-triggered loading to skills:

> *"Rules load into context every session or when matching files are opened. For task-specific instructions that don't need to be in context all the time, use [skills](/en/skills) instead, which only load when you invoke them or when Claude determines they're relevant to your prompt."*

If a user's CLAUDE.md says "on demand" for a rule, that's their mental model — the actual loading is either always or path-scoped.

## Path-scoping — the field

The exact field name is `paths:`. The documented format is a YAML list of glob strings:

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "src/**/*.{ts,tsx}"
  - "lib/**/*.ts"
---
```

Globs support brace expansion (`{ts,tsx}`) and recursive `**`. Forward-slash paths are canonical (cross-platform).

**What it matches against:** the file being **read** by Claude. Per docs: *"Path-scoped rules trigger when Claude reads files matching the pattern, not on every tool use."*

## Known parser bugs (community-tested)

### Issue #17204 — `paths:` YAML list inconsistent

The documented form has known parser bugs. Community test matrix:

| Frontmatter form | Loads? |
|---|---|
| No frontmatter | ✅ YES — unconditional load |
| `globs: "**/*.ts"` (undocumented field, comma-separated) | ✅ YES |
| `paths: **/*.ts` (unquoted scalar) | ✅ YES |
| `paths: "**/*.ts"` (quoted scalar) | ❌ silently fails |
| YAML list (the documented form) | ⚠️ inconsistent |

Workaround: prefer no frontmatter when always-loading; for path-scoping, the unquoted scalar form is most reliable. The undocumented `globs:` field is what some power-users have switched to.

### Issue #23478 — Read-only trigger

Path-scoped rules trigger on **Read**, not on Write/Create. So a `**/*.md` rule fires when Claude opens an existing `.md` file, but NOT when Write creates a brand-new one. The docs confirm this implicitly: *"Path-scoped rules trigger when Claude reads files matching the pattern."*

This means: you can't write a rule that fires when Claude is *creating* a new file with a specific name. Workaround: scope to file extensions or directories that already exist.

### Issue #13905 — Glob quoting

Glob patterns starting with `*` or `{` need quoting in YAML — the `*` is a reserved alias indicator. `paths: *.ts` is technically invalid YAML.

## Loading order / priority

- **User-scope rules load BEFORE project rules** — but project rules win on conflict. If `~/.claude/rules/foo.md` and `<project>/.claude/rules/foo.md` both have content, both load, but the project version wins on contradictions.
- **Within a single scope** — load order is not specified. Don't rely on it for behaviour.
- **CLAUDE.md vs rules** — both load with the same priority when `paths` is absent. If you put the same instruction in both, both load.

## Plugin manifest — `installed_plugins.json`

Path: `~/.claude/plugins/installed_plugins.json`

Shape:

```json
{
  "version": 2,
  "plugins": {
    "<plugin-name>@<marketplace-name>": [
      {
        "scope": "user",
        "installPath": "/Users/<user>/.claude/plugins/cache/<marketplace>/<plugin>/<version>",
        "version": "1.0.0",
        "installedAt": "2026-03-04T12:53:50.359Z",
        "lastUpdated": "2026-03-16T14:03:57.376Z",
        "gitCommitSha": "..."
      }
    ]
  }
}
```

To uninstall: remove the `<plugin-name>@<marketplace-name>` key from `plugins`. The cache directory at `installPath` is just disk space — Claude Code reads the manifest at session start, so removing the manifest entry de-registers all of the plugin's hooks, MCP servers, slash commands, agents, and skills.

## Standalone skills — `~/.claude/skills/`

Each skill is a directory containing `SKILL.md` (with YAML frontmatter — `name` and `description` required, plus optional fields per <https://code.claude.com/docs/en/skills>):

```
~/.claude/skills/
├── my-skill/
│   ├── SKILL.md
│   ├── references/
│   ├── scripts/
│   └── assets/
└── another-skill/
    └── SKILL.md
```

To uninstall, quarantine the directory rather than `rm -rf`-ing it — the audit ships `scripts/quarantine.sh` for this. The destructive form would be:

```bash
SESSION=$(bash <skill-dir>/scripts/quarantine.sh init)
bash <skill-dir>/scripts/quarantine.sh add "$SESSION" ~/.claude/skills/<skill-name>
```

No manifest edit needed — standalone skills register purely by directory presence under `~/.claude/skills/`. Removing the directory de-registers the skill. The quarantine path is reversible for 7 days via `restore.sh`; a direct `rm -rf` is not, and contradicts the audit's safety model.

Note: an older path `~/.claude/plugins/installed/` is sometimes seen in docs or third-party guides. As of Claude Code 1.x, standalone skills live at `~/.claude/skills/`. Always verify the path before assuming.

## Skill frontmatter — distinct from rule frontmatter

Skills support many fields (name, description, when_to_use, allowed-tools, model, etc. — see official docs). Rules support only `paths`. **Don't conflate them.**

If you find a `.md` file under `~/.claude/rules/` with skill-style frontmatter (like `when_to_use:` or `allowed-tools:`), the loader ignores those fields. If you find a `SKILL.md` with `paths:` only and no `name` or `description`, the skill loader will reject it.

## When in doubt

Use the `InstructionsLoaded` hook (per <https://code.claude.com/docs/en/hooks#instructionsloaded>) to log exactly which instruction files load each session, when, and why. This is the canonical way to verify your rules are working as expected.

## Sources

- Official memory + rules docs: <https://code.claude.com/docs/en/memory>
- Official skills docs: <https://code.claude.com/docs/en/skills>
- Official subagents docs: <https://code.claude.com/docs/en/sub-agents>
- Issue #17204: <https://github.com/anthropics/claude-code/issues/17204>
- Issue #23478: <https://github.com/anthropics/claude-code/issues/23478>
- Issue #13905: <https://github.com/anthropics/claude-code/issues/13905>
