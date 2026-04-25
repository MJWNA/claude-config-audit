# Evals

Trigger evals for the `claude-config-audit` skill. Used by skill-creator's `run_loop.py` description-optimizer and by anyone running manual triggering tests.

## Format

`evals.json` follows the [skill-creator schema](https://github.com/anthropics/claude-plugins-official/tree/main/skills/skill-creator/references/schemas.md):

- 10 should-trigger queries — realistic phrasings where the skill genuinely is the right tool
- 10 should-not-trigger queries — near-misses that share keywords ("audit", "plugins", "rules", "clean up", "delete") but actually need a different tool

## Why these queries

The hard cases for this skill are the negative ones — "audit my AWS bill" shares "audit", "review my wordpress plugins" shares "plugins", "clean up my eslint rules" shares "clean up rules". The skill description has to be specific enough that those don't match while still being permissive enough for the 10 positive cases (which include terse phrasings like "/audit-skills" and conversational ones like "im looking at my plugin list and i can barely scroll through it").

One query (`noise-8`) is intentionally an edge case — a user asking about hook/token security could legitimately want either this skill (for the security-pass agent) or a more focused security tool. Either trigger outcome is acceptable; it's there to confirm the skill description doesn't *over*-trigger on adjacent security work.

## Running the description optimiser

```bash
# From the skill-creator plugin directory:
python -m scripts.run_loop \
  --eval-set <path>/evals/evals.json \
  --skill-path <path-to-claude-config-audit> \
  --max-iterations 5 \
  --verbose
```

The optimiser will run each query 3 times to get a reliable trigger rate, then propose description tweaks until trigger accuracy plateaus.

## Adding new evals

When you find a phrasing the skill missed (false negative) or one it incorrectly fired on (false positive), add it here. Negative tests are more valuable than positive ones — they're how we keep the description from creeping toward keyword-stuffing.
