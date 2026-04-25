# Philosophy

Why this skill exists, what it optimises for, and what it deliberately avoids.

## The problem

Claude Code installations rot. Not because anything breaks — because the installation grows faster than the deletion bar.

Each new plugin lowers the cost of trying things. Each new skill captures a moment of insight. Each new rule encodes a correction. The problem isn't any single addition — it's that nothing ever gets removed. After six months, the user has 50 plugins, 25 skills, and 14 rules, and they don't know which are pulling weight.

The cost is real:

- **Context bloat** — every loaded skill description, every always-on rule, every plugin's tool definitions inflate the system prompt. This costs tokens and dilutes attention.
- **Cognitive load** — slash command lists scroll for pages. The `/plugin` UI takes seconds to render. The user can't remember what's installed.
- **Silent breakage** — references to deleted skills point nowhere. Rules reference plugins that were uninstalled. The user doesn't notice until something goes weirdly wrong.

The user could clean this up by hand. But making 50 keep/delete decisions without evidence is paralysing. So they don't.

## The principle

**Don't make decisions without evidence.**

The session-history archaeology is the heart of this skill. Every plugin, every skill, every rule has a usage signature: real `Skill` tool calls, user-typed slash commands, Bash patterns, MCP invocations. We can count them. The agents do.

Evidence converts paralysis into a tractable decision. "Should I keep this plugin?" becomes "I haven't invoked this in 90 days, the only competing tool I use 325 times more often, and the original use case is gone." That's an easy delete.

## Why the dual-half structure

Skills (executable layer) and rules (instruction layer) need different audit treatments:

**Skills** are about **invocation**. You either called it or you didn't. The agents count.

**Rules** are about **content quality**. A rule that has never been "invoked" might still be doing its job — preventing mistakes — silently. The audit needs to assess content (is this fresh? does this duplicate something?) and the agents read.

Trying to use the same workflow for both halves loses information. Splitting them lets each half ask its own right questions.

## Why interactive HTML for decisions

We tried doing decisions inline in chat. It doesn't work. With 50 items:

- The user scrolls past their own decisions and forgets which they've already made
- They can't see how many are left
- They lose context about *why* a particular item should be deleted (the agent verdict scrolls off-screen)
- They can't easily change their mind on item #12 after they've reached item #38

The HTML solves all of these:

- Cards collapse so only the open one is visible
- Live counters show progress
- Agent verdict + evidence are inline with the decision UI
- Decisions persist via localStorage, so they can step away and come back
- Mismatch + undecided filters help them sweep up at the end

Chat handles the bookends (discovery summary, confirmation of plan). HTML handles the middle.

## Why parallel agents

Single-agent sequential analysis of 50 items would:

1. Take 10x longer
2. Use 10x more tokens (each item re-enters context)
3. Give worse output (last item gets less attention than first)
4. Mix categories (overlap analysis between Slack-MCP and SLACK_BOT_TOKEN curl is impossible if the agent is also trying to analyse Sentry)

Parallel agents per category: each sees only its slice, finishes in parallel, returns a structured report. The synthesis step combines them.

This is also a deliberate teaching pattern. Many users won't realise sub-agents can be dispatched in parallel until they see this skill do it. Reading the workflow exposes the pattern for them to use elsewhere.

## What we explicitly don't do

### We don't recommend uniformly

Some skills will say "always delete plugin X." We don't. The same plugin can be load-bearing for one user and dead weight for another. The recommendation must be grounded in *this user's* session history.

### We don't optimise for a metric

The agents don't try to "maximise context savings" or "minimise install size." They report evidence and let the user decide. A zero-invocation plugin might still be the right keep for someone who just installed it last week.

### We don't auto-execute without confirmation

Even in auto mode, even after the user has approved the plan in the markdown report, the skill shows the exact commands and waits for "go." The cost of one extra round-trip is small. The cost of an unwanted deletion is large.

### We don't generalise the agents

Each agent prompt is tuned for the specific category. We don't have one "audit everything" prompt. The bucket-specific framing produces sharper analysis than a generic prompt.

### We don't compete with `/plugin`

Claude Code's built-in `/plugin` command is the right tool for installing and managing plugins one at a time. This skill is for the audit moment — when the user is asking "which 18 of these 50 should go." After the audit, `/plugin` resumes its day job.

## What we trade off

### Speed for evidence

A "delete everything you haven't used in 90 days" recommendation can be made by a script in 30 seconds. The skill takes 30-60 minutes because the agents read context, examine overlap, and explain reasoning. The slow part is the agents producing per-item evidence so the user can make grounded decisions.

If the user wants speed without evidence, this is the wrong tool. They should use a script.

### Customisation for repeatability

The HTML templates are opinionated. The agent prompts are opinionated. The categorisation is opinionated. A user who wants different categories has to fork the skill.

We picked opinionation over flexibility because opinionation produces consistent, comparable audit outputs across users. A community of users who all run the same audit can compare notes about which plugins are dead weight in general — the consistency is more valuable than the per-user customisation.

### Comprehensiveness for context

The skill's references files (workflow playbooks) are detailed. The HTML templates are big. The SKILL.md itself is ~250 lines. This trades context cost for completeness — when Claude is running the skill, it needs to know what to do at every phase, and "go look it up" doesn't work mid-execution.

The progressive-disclosure pattern (only read references when reaching that phase) compensates partly. But the SKILL.md itself can't be smaller than it is and still describe the workflow.

## What we hope happens

A user runs this skill once. They cut their installation in half, learning their actual usage patterns in the process. They see which patterns recurred ("I keep installing Sentry plugins and never wiring up Sentry — what's the pattern?"). They notice which kinds of items survive vs get deleted ("rules survive better than skills — interesting").

They also see the parallel-agent + interactive-HTML decision pattern. The next time they have a 50-item decision in any domain (which dependencies to upgrade, which features to ship, which clients to keep) they reach for the same shape.

The skill teaches by doing.
