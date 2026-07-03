---
name: model-audit
description: Audit which Claude model handled Claude Code sessions. Use when the user asks "what models did I use", "was this session on Fable 5 or Opus", "which model ran my sessions for project X", "was my request downgraded to another model", or wants a per-session model usage report over a time window.
argument-hint: "[days|all] [project-hint]"
---

# Model Audit

Reports which model produced every assistant response in the user's Claude Code
sessions, by reading the transcript JSONL files under `~/.claude/projects/`.
Each assistant message carries a `"model"` field with the exact model ID that
produced it — this is the ground truth, per message, so mid-session fallbacks
are visible.

## Invocation arguments

Arguments given: $ARGUMENTS

Interpret the tokens above as follows (they combine freely):

- Empty → run the default 7-day audit across all projects.
- A number → use it as the day window (e.g. `30` = last 30 days).
- `all` → no date filter (all time).
- Any other token → a project hint: resolve it to a transcript folder with
  `ls ~/.claude/projects/ | grep -i <hint>` and scope the run via
  `CLAUDE_PROJECTS_DIR` (method 1 under "Filter to one project" below). If the
  hint matches several folders, list them and ask which one, or audit each if
  only two or three match.
- Example: `/model-audit 30 vg-site` = last 30 days, only the vg-site project.

After running, present the session table and totals, applying the
interpretation rules in "Read the output".

## Run the audit

The bundled script lives in this skill's directory. Run it with a time window:

```bash
<skill-dir>/list-session-models.sh          # last 7 days (default)
<skill-dir>/list-session-models.sh 30       # last N days (any number)
<skill-dir>/list-session-models.sh all      # all time (no date filter)
```

Any other argument prints usage and exits nonzero.

## Filter to one project

Transcript folders are the flattened working-directory path (slashes become
dashes), e.g. `/Users/vg/experiments/vg-site/vijay` becomes
`-Users-vg-experiments-vg-site-vijay`. Two ways to scope the audit:

1. Point the script at that one folder:
   ```bash
   CLAUDE_PROJECTS_DIR=~/.claude/projects/-Users-vg-experiments-vg-site-vijay \
     <skill-dir>/list-session-models.sh all
   ```
2. Or run the full audit and filter rows by project substring:
   ```bash
   <skill-dir>/list-session-models.sh all | grep -i vg-site
   ```

Note: with method 2 the "Totals" block at the bottom still covers all
projects, not just the filtered rows. Use method 1 when the user wants
per-project totals. To find the right folder name, list candidates first:
`ls ~/.claude/projects/ | grep -i <project-hint>`.

## Read the output

One row per session, newest first, then totals:

```
LAST ACTIVE        PROJECT                                SESSION                            MODELS (responses)
2026-07-02 11:18   -Users-vg-experiments-linkedin-scrape  4a347153-4458-47f8-...             claude-fable-5(278)
2026-07-02 07:53   -Users-vg-experiments-linkedin-scrape  1a89419d/agent-ab3a2f9e5caae8685   claude-opus-4-8(21)
```

Interpretation rules (carry these into your answer):

- MODELS counts are per response. A session that fell back mid-way shows both
  models with their proportions.
- SESSION values like `1a89419d/agent-...` are subagent transcripts, resolved
  to their owning project and prefixed with the first 8 chars of the parent
  session that spawned them. Subagents legitimately run on different models
  (explicit overrides, Explore/utility routing) — they never handle the main
  conversation turns. A main-session row showing 100% one model means every
  conversation turn ran on that model.
- Resumed or forked sessions copy prior history into a new session file (same
  message IDs in both), so the same responses appear in two rows and the
  cross-session totals overcount resumed conversations. Per-session rows are
  accurate.
- `"model":"<synthetic>"` entries are harness-injected error messages, not
  model responses; the script filters them out.
- Realistic downgrade paths to check when the user suspects one: `/fast` mode
  (runs on Opus), a plan usage-limit fallback (announced in the UI), or an
  explicit subagent/workflow model override.

## Do not hand-roll the grep

If you inspect transcripts directly instead of using the script, anchor the
pattern on `"message":{"model":"`. A bare `"model":"..."` grep also matches
model-override parameters inside Agent tool-call inputs (e.g. the main model
spawning an Explore subagent with `model: "opus"`) and misreports them as
responses. Only the `message.model` field says which model actually produced
a response.
