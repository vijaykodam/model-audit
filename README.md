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

## Three ways to verify the model, quickest to most authoritative

### 1. `/status` or `/model` in the session

Shows the model the session is currently pinned to. If fast mode is on
(toggled with `/fast`), the status reflects that — fast mode runs on Opus
with faster output, so toggling it is the one common way a session silently
moves off Fable 5.

### 2. Ask about the environment

Each session's system prompt states the exact model ID (e.g.
`claude-fable-5`), so the model itself can report what it is running as.

### 3. Inspect the transcript JSONL (ground truth)

Every assistant message in
`~/.claude/projects/<project-dir>/<session-id>.jsonl` carries a `"model"`
field with the exact model ID that produced it. This is per-message, not
per-session, so any mid-session fallback is visible. That is what the script
automates; a one-liner for a single project:

```bash
grep -oh '"message":{"model":"claude-[^"]*"' ~/.claude/projects/<project-dir>/*.jsonl | sort | uniq -c
```

## What model changes are normal vs. suspicious

- The main conversation model does not get silently downgraded mid-session
  in normal operation.
- Different models legitimately appear for subagents (e.g. Explore agents
  routed to Sonnet/Haiku by preference) and for small internal utilities
  like bash-command description generation, which use Haiku. These show up
  as separate transcript entries (subagent transcripts live under a
  `subagents` directory) but never handle the actual coding turns.
- Realistic downgrade scenarios: `/fast` was toggled (Opus-based), a plan
  usage limit triggered a fallback model (Claude Code announces this in the
  UI), or a subagent/workflow had an explicit model override.
- `"model":"<synthetic>"` entries are harness-injected error messages, not
  real model responses; the script filters them out.

## How the script works

- `find ... -mtime -<days>` selects transcripts touched within the window
  (a session file's mtime is its last activity); `all` drops the mtime
  filter entirely and scans every transcript on disk.
- `grep -o '"message":{"model":"[^"]*"'` pulls the model ID from each
  recorded assistant message; `<synthetic>` entries are dropped.
- The grep is anchored on `"message":{"model":` deliberately. A bare
  `"model":"..."` pattern also matches model-override parameters inside
  Agent tool-call inputs — e.g. the main model spawning an Explore
  subagent with `model: "opus"` — and would misreport those as responses
  from an "opus" model. Only the `message.model` field says which model
  actually produced a response.
- Counts are per response, so a session that fell back mid-way shows both
  models with their proportions.
- Rows sorted newest-first; PROJECT is the flattened working-directory
  path Claude Code uses as the transcript folder name.
- Subagent transcripts live at
  `<project>/<parent-session-id>/subagents/agent-*.jsonl`. The script
  resolves them to their owning project, and formats SESSION as
  `<parent-session-first-8-chars>/agent-<id>` so each subagent row is
  traceable to the interactive session that spawned it.

## Reading the results

- If your coding turns were downgraded, the session row shows
  `claude-opus-4-8` (or another model) counts inside a session you
  expected to be Fable 5.
- Subagent work appears as separate rows (SESSION looks like
  `1a89419d/agent-...`), so a main-session row showing 100% one model
  means every conversation turn ran on that model.
- Resumed or forked sessions get a new session file that includes a copy
  of the prior history, so the same responses can appear in two rows
  (same message IDs in both files). Totals across sessions therefore
  overcount conversations that were resumed; per-session rows are still
  accurate.

## Related built-in tools

- `/usage` shows plan quota consumption (session/weekly limits) — no model
  or per-project breakdown.
- The `session-report` plugin aggregates token usage by project, skill, and
  subagent type from the same transcripts — but does not report model IDs.

This tool covers the third dimension: model provenance per session.
