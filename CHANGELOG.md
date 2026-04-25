# Changelog

All notable changes to claude-config-audit are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-04-25

### Added
- Initial release
- Skills audit half — parallel-agent scan + HTML decision tool + safe cleanup
- Rules audit half — parallel-agent scan + HTML decision tool with full proposed file content for new rule candidates
- Two production-ready HTML templates (`skills-audit-template.html`, `rules-audit-template.html`) with localStorage persistence, mismatch filtering, bulk actions, and markdown export
- Five reference playbooks covering workflow, safety, parallel-agent patterns, and the official Claude Code rule spec (with citations to docs and known parser bugs in issues #17204, #23478, #13905)
- Two scripts for prerequisite checking and config discovery
- Four docs explaining philosophy, workflow, safety, and customisation
- One sample output documenting what a real audit run produces

### Pattern origin
Workflow developed across two production audits on a Claude Code installation with 25 plugins, 25 standalone skills, and 14 user-scope rules. Net change after audit: 50 → 32 items, with full evidence-based justification per item.
