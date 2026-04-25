# Security Policy

## Reporting a vulnerability

This skill modifies user-scope Claude Code config — moving plugin caches and skill directories into a 7-day quarantine, editing `installed_plugins.json`, and writing/editing rule files. Anything that could escape that scope, bypass the confirmation gate, or lose user data has high blast radius. Report security bugs privately, not via public issues.

## How to report

Use GitHub's private vulnerability reporting:

1. Go to <https://github.com/MJWNA/claude-config-audit/security/advisories>
2. Click **Report a vulnerability**
3. Describe the issue with reproduction steps

If you can't use private reporting for any reason, contact the maintainer directly via the email address listed on the [@MJWNA GitHub profile](https://github.com/MJWNA).

## What counts as a security issue

The bar is "did the skill do something it wasn't supposed to do, where the consequence is loss of user data or escalated capability?"

Specifically — these are security bugs:

- A way for the skill to modify state outside `~/.claude/`
- A way to bypass the confirmation gate before destructive operations (deletion executes without explicit "go")
- A way to lose data that wasn't in the user's stated deletion plan
- A way to corrupt `installed_plugins.json` such that the quarantine snapshot can't restore it
- Path traversal in any of the scripts (e.g. crafted plugin names that escape the cache directory during cleanup)
- Shell or code injection through quarantine session paths, agent output, or user-controlled filenames
- Code execution from agent output (e.g. agent returns content that gets evaluated rather than displayed)

These are NOT security bugs (file as regular bugs):

- Wrong agent verdicts (the agent recommends DELETE for something the user wants to keep)
- Bad UX in the HTML decision tools
- Documentation errors
- Performance issues
- Workflow steps in the wrong order (assuming no data loss)

## Response time

The maintainer aims to acknowledge security reports within 7 days and ship a fix or mitigation within 30 days for confirmed issues. This is best-effort — this is an open-source project, not a commercial product.

## Scope

The skill operates strictly within `~/.claude/` and never touches anything outside that directory. If you find a way to make it operate outside that scope, that's a security issue.

The skill never makes outbound network calls — everything runs locally. If you find network calls being added (e.g. via a malicious agent prompt), that's a security issue.

The skill respects Claude Code's permission system — if Claude Code refuses a tool call, the skill doesn't attempt to bypass it. If you find a bypass, that's a security issue.

## Disclosure

After a fix ships, the security advisory will be published with credit to the reporter (unless they prefer to remain anonymous).
