# model-audit

A Claude Code skill — installable as a plugin — that audits which Claude model
handled your sessions — e.g. to confirm your coding requests ran on Fable 5
and were not served by a different model (Opus 4.8, a fallback, etc.).

It reads the session transcript JSONL files Claude Code writes under
`~/.claude/projects/`. Every assistant message there carries a `"model"`
field with the exact model ID that produced it — a per-message, ground-truth
audit trail.

## Install

### As a plugin via the vijaykodam marketplace (recommended)

```
/plugin marketplace add vijaykodam/claude-plugins
/plugin install model-audit@vijaykodam
```

Or from your shell, outside a session:

```bash
claude plugin marketplace add vijaykodam/claude-plugins
claude plugin install model-audit@vijaykodam
```

Run `/reload-plugins` (or restart Claude Code) to activate. The skill is then
available as the `/model-audit:model-audit` slash command and is also invoked
automatically when you ask things like "what models did I use for project X?"
or "was this session downgraded from Fable 5?".

### As a plugin directly from this repo

This repo doubles as its own single-plugin marketplace:

```
/plugin marketplace add vijaykodam/model-audit
/plugin install model-audit@model-audit
```

### As a personal skill (clone + symlink)

```bash
git clone https://github.com/vijaykodam/model-audit.git
ln -s "$(pwd)/model-audit/skills/model-audit" ~/.claude/skills/model-audit
```

This variant registers the skill without the plugin namespace, so the slash
command is the shorter `/model-audit`. The symlink keeps the installed skill
in sync with the repo.

## Use the script directly (no skill needed)

```bash
skills/model-audit/list-session-models.sh          # last 7 days (default)
skills/model-audit/list-session-models.sh 30       # last 30 days (any number works)
skills/model-audit/list-session-models.sh all      # all time (no date filter)
CLAUDE_PROJECTS_DIR=~/.claude/projects/-Users-vg-myproject skills/model-audit/list-session-models.sh  # one project
```

Any other argument prints usage and exits nonzero. No dependencies beyond
standard macOS/Linux tools (bash, find, grep, sed, awk, stat); handles both
BSD and GNU `stat`.

### Example output

```
Claude Code sessions active in the last 7 day(s)

LAST ACTIVE        PROJECT                                SESSION                               MODELS (responses)
2026-07-03 09:47   -vijay-projects-project3    85f5d9a6-ec9f-4dc2-...                claude-fable-5(24)
2026-07-02 11:18   -vijay-projects-project1    4a347153-4458-47f8-...                claude-fable-5(278)
2026-07-02 07:53   -vijay-projects-projecy1    1a89419d/agent-ab3a2f9e5caae8685      claude-opus-4-8(21)
2026-06-30 18:06   -vijay-projects-project3    a4b9c607-b1e8-4c92-...                claude-opus-4-8(128)

Totals across all sessions:
     598  claude-fable-5
     504  claude-opus-4-8
      51  claude-haiku-4-5-20251001
```

## Reading the results

When invoked as a skill, `/model-audit` runs the audit and presents the
session table and totals with these interpretation rules applied; they hold
equally if you read the script output yourself.

- MODELS counts are per response, so a session that changed model mid-way
  shows both models with their proportions. A downgrade shows up as
  `claude-opus-4-8` (or another model) counts inside a session you expected
  to be Fable 5.
- Subagent work appears as separate rows (SESSION looks like
  `1a89419d/agent-...`, prefixed with the parent session that spawned it).
  Subagents legitimately run on different models but never handle the main
  conversation turns — so a main-session row showing 100% one model means
  every conversation turn ran on that model.
- Resumed or forked sessions get a new session file that includes a copy
  of the prior history, so the same responses can appear in two rows
  (same message IDs in both files). Totals across sessions therefore
  overcount conversations that were resumed; per-session rows are still
  accurate.
- `"model":"<synthetic>"` entries in transcripts are harness-injected error
  messages, not real model responses; the audit filters them out.

## Related built-in tools

Claude Code's built-in usage commands were checked first, but none of them
report model provenance — which model actually produced each response. That
is the gap `/model-audit` fills. How each differs:

- `/usage` shows plan quota consumption (session/weekly limits) — no model
  IDs, no per-project or per-session breakdown.
- `/cost` and `/context` show token and cost figures for the current session
  only — no history across sessions, no model provenance.
- The `session-report` plugin aggregates token usage by project, skill, and
  subagent type from the same transcripts — but does not report model IDs.
- `/model-audit` reads the per-message `"model"` field from the transcripts:
  per-session, per-response model IDs across all projects and any time
  window.
