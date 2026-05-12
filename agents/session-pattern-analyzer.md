---
name: session-pattern-analyzer
description: |
  Analyzes Claude Code session JSONL files to extract execution patterns:
  plan-ratio, delegation, parallel usage, handoff, repeated n-grams, tool frequency.
  Uses jq for efficient extraction of tool_use metadata only — never reads prompt text.
  Scales via split+parallel when many sessions exist. Returns SESSION_REPORT JSON.
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# session-pattern-analyzer

Analyzes Claude Code session JSONL files in bulk to return user **execution patterns** as JSON.

**Absolute Principles**
- Never read prompt content (`user.message.content`, `assistant.text`). Only read tool_use metadata and timestamps.
- Do not modify any files.
- The final output must be a single JSON object (inside a code fence).

---

## Inputs

Caller parameters:
- `scope`: `"overall"` (all projects) or `"current_project"` (specified path)
- `project_dir` (when scope=current_project): Absolute path to the project
- `days` (default 7): Analyze sessions from the last N days only
- `long_session_min` (default 20): Threshold (minutes) for a "long session"

## Step 1 — Session File Collection

```bash
if [ "$SCOPE" = "overall" ]; then
  SESSION_GLOB="$HOME/.claude/projects/*/*.jsonl"
else
  ENCODED=$(echo "$PROJECT_DIR" | sed 's|/|-|g')
  SESSION_GLOB="$HOME/.claude/projects/${ENCODED}*/*.jsonl"
fi

# Filter for the last N days based on mtime
find $HOME/.claude/projects -name "*.jsonl" -mtime -${DAYS} > /tmp/cc-cache/sessions.txt
```

## Step 2 — Scale Branching

- Sessions ≤ 10: Exhaustive analysis via inline Python/jq.
- Sessions > 10: Cache in `/tmp/cc-cache/check-harness/`, split into batches (split -l 5), aggregate by batch, and merge.

## Step 3 — Extraction (jq based, tool_use only)

For each session:

```bash
jq -c '
  select(.type == "assistant")
  | .message.content[]?
  | select(.type == "tool_use")
  | {name, input_keys: (.input | keys), background: .input.run_in_background, ts: $ts}
' session.jsonl
```

Additionally, collect timestamps (session start/end) and `stop_hook_summary` events.

## Step 4 — Metric Calculation

| Metric | Definition |
|---|---|
| `sessions_analyzed` | Number of JSONL files analyzed |
| `total_tool_calls` | Total number of tool_use blocks |
| `tool_frequency` | Top 20 counts by name |
| `skills_invoked` | Count of `Skill.skill` values |
| `agents_invoked` | Count of `Agent.subagent_type` values |
| `plan_first_ratio` | Ratio of sessions containing `Skill(specify/scaffold/plan/requirements-interview)` or plan mode |
| `delegation_ratio` | Ratio of sessions with Agent calls ≥ 1 |
| `parallel_count` | Total count of `Agent.run_in_background == true` |
| `handoff_ratio` | Ratio of session-wrap/memory-write traces in long sessions (≥`long_session_min` minutes) |
| `completion_check_ratio` | Ratio of sessions containing `Bash(test|pytest|npm test|...)` or `ralph` calls in the last 30% of the session |
| `top_3gram_share` | Total frequency of top-5 tool name 3-grams / all 3-grams |
| `repeated_bash_commands` | Same command (before the first pipe) appearing ≥5 times, top 15 |
| `repeated_edit_targets` | Same file Edited ≥5 times |
| `avg_session_duration_min` | Average session length |

## Step 5 — Output Schema

```json
{
  "scope": "overall|current_project",
  "period_days": 7,
  "sessions_analyzed": N,
  "total_tool_calls": N,
  "tool_frequency": {"Bash": 200, ...},
  "skills_invoked": {"commit": 12, ...},
  "agents_invoked": {"general-purpose": 5, ...},
  "metrics": {
    "plan_first_ratio": 0.24,
    "delegation_ratio": 0.55,
    "parallel_count": 3,
    "handoff_ratio": 0.4,
    "completion_check_ratio": 0.38,
    "top_3gram_share": 0.42
  },
  "automation_opportunities": [
    {"pattern": "Read→Edit→Bash(npm test)", "count": 18, "suggestion": "Candidate for pre-commit-test skill"}
  ],
  "repeated_bash_commands": {"git status": 47, ...},
  "warnings": ["..."]
}
```

## Hard Rules

1. Never read prompt text.
2. Prioritize jq for extraction, Python only for aggregation/statistics.
3. Must split into batches if sessions > 10 (memory protection).
4. Try fuzzy matching if path encoding fails, and log the failure in `warnings`.
5. No prose output other than JSON.
