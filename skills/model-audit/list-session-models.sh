#!/usr/bin/env bash
# list-session-models.sh — models used per Claude Code session in the last N days
#
# Scans Claude Code session transcripts (~/.claude/projects/**/*.jsonl) whose
# files were modified within the window, and counts the "model" field recorded
# on each assistant message. This is the ground-truth audit: every response in
# a transcript carries the exact model ID that produced it.
#
# Usage:
#   ./list-session-models.sh          # last 7 days (default)
#   ./list-session-models.sh 30       # last 30 days (any number of days works)
#   ./list-session-models.sh all      # all time (no date filter)
#
# Env:
#   CLAUDE_PROJECTS_DIR  override the transcript root (default ~/.claude/projects)

set -euo pipefail

WINDOW="${1:-7}"
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

if [[ "$WINDOW" == "all" ]]; then
  MTIME_ARGS=()
  WINDOW_LABEL="all time"
elif [[ "$WINDOW" =~ ^[0-9]+$ ]]; then
  MTIME_ARGS=(-mtime -"$WINDOW")
  WINDOW_LABEL="the last $WINDOW day(s)"
else
  echo "Usage: $(basename "$0") [days|all]   (default: 7)" >&2
  exit 1
fi

if [[ ! -d "$PROJECTS_DIR" ]]; then
  echo "ERROR: transcript directory not found: $PROJECTS_DIR" >&2
  exit 1
fi

tmp_rows="$(mktemp)"
tmp_summary="$(mktemp)"
trap 'rm -f "$tmp_rows" "$tmp_summary"' EXIT

find "$PROJECTS_DIR" -type f -name '*.jsonl' ${MTIME_ARGS[@]+"${MTIME_ARGS[@]}"} -print0 |
  while IFS= read -r -d '' f; do
    # Extract model IDs from assistant messages only. The anchor on
    # '"message":{"model":' is deliberate: a bare '"model":"..."' pattern also
    # matches model-override parameters inside Agent tool-call inputs (e.g.
    # spawning an Explore subagent with model "opus") and would count them as
    # responses. Drop "<synthetic>" (harness-injected error messages).
    extracted="$(grep -o '"message":{"model":"[^"]*"' "$f" 2>/dev/null |
      sed 's/.*"model":"//; s/"$//' |
      grep -v '^<synthetic>$' || true)"
    [[ -z "$extracted" ]] && continue

    models="$(printf '%s\n' "$extracted" | sort | uniq -c | sort -rn |
      awk '{printf "%s(%s) ", $2, $1}')"

    if [[ "$(uname)" == "Darwin" ]]; then
      mtime="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$f")"
    else
      mtime="$(date -d "@$(stat -c '%Y' "$f")" '+%Y-%m-%d %H:%M')"
    fi
    # Subagent transcripts live at <project>/<parent-session>/subagents/;
    # resolve them to their owning project and label them with the parent
    # session's short ID so the row is traceable to the session that spawned it.
    parent_dir="$(dirname "$f")"
    if [[ "$(basename "$parent_dir")" == "subagents" ]]; then
      parent_session="$(basename "$(dirname "$parent_dir")")"
      project="$(basename "$(dirname "$(dirname "$parent_dir")")")"
      session="${parent_session:0:8}/$(basename "$f" .jsonl)"
    else
      project="$(basename "$parent_dir")"
      session="$(basename "$f" .jsonl)"
    fi

    printf '%-17s  %-45s  %-37s  %s\n' "$mtime" "$project" "$session" "$models" >> "$tmp_rows"
    printf '%s\n' "$extracted" >> "$tmp_summary"
  done

if [[ ! -s "$tmp_rows" ]]; then
  echo "No sessions with model activity found in $WINDOW_LABEL."
  exit 0
fi

echo "Claude Code sessions active in $WINDOW_LABEL"
echo
printf '%-17s  %-45s  %-37s  %s\n' "LAST ACTIVE" "PROJECT" "SESSION" "MODELS (responses)"
sort -r "$tmp_rows"

echo
echo "Totals across all sessions:"
sort "$tmp_summary" | uniq -c | sort -rn | awk '{printf "  %6d  %s\n", $1, $2}'
