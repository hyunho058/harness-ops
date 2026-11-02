#!/usr/bin/env bash
# TT6 — acceptance tests for R6.1, R6.2, R6.5, R6.6, R6.7 (project signals; spec D14, D15, D18, D6, D2).
# Black box: drives skills/check-harness/scripts/project_signals.py through its CLI only.
# Git-dated cases (R6.3, R6.4, R6.8) live in tt6_project_signals_git_test.sh.
# Run from the repo root: bash skills/check-harness/tests/tt6_project_signals_test.sh
set -u

SCRIPT="skills/check-harness/scripts/project_signals.py"
# Never leave __pycache__ in the repo.
export PYTHONDONTWRITEBYTECODE=1

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
# Keep any git the script runs from discovering a repository above the fixtures.
export GIT_CEILING_DIRECTORIES="$SCRATCH"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$SCRATCH/home-default/.claude"
export HOME="$SCRATCH/home-default"

FAILS=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1: $2"; FAILS=$((FAILS + 1)); }

# run_ps NAME HOME_DIR ROOT [EXTRA_ARGS...]
# Runs the script; leaves stdout in $SCRATCH/NAME.out, stderr in $SCRATCH/NAME.err.
# Returns 0 only when the script exists, exits 0 and prints a JSON object.
run_ps() {
  local name="$1" home="$2" root="$3"
  shift 3
  local out="$SCRATCH/$name.out" err="$SCRATCH/$name.err" rc
  if [ ! -f "$SCRIPT" ]; then
    fail "$name" "$SCRIPT does not exist"
    return 1
  fi
  HOME="$home" python3 "$SCRIPT" --project-root "$root" "$@" >"$out" 2>"$err"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$name" "exit $rc, want 0 (stderr: $(head -c 400 "$err"))"
    return 1
  fi
  if ! jq -e 'type == "object"' "$out" >/dev/null 2>&1; then
    fail "$name" "stdout is not a JSON object: $(head -c 400 "$out")"
    return 1
  fi
  return 0
}

# check NAME JQ_EXPR [JQ_ARGS...] — passes when the expression is true on NAME's stdout.
check() {
  local name="$1" expr="$2"
  shift 2
  if jq -e "$@" "$expr" "$SCRATCH/$name.out" >/dev/null 2>&1; then
    ok "$name"
  else
    fail "$name" "expected: $expr; got: $(head -c 800 "$SCRATCH/$name.out")"
  fi
}

# hooks_file PATH EVENT MATCHER COMMAND — Claude Code hooks shape ({"hooks": {EVENT: [...]}}).
hooks_json() {
  jq -n --arg e "$2" --arg m "$3" --arg c "$4" \
    '{hooks: {($e): [{matcher: $m, hooks: [{type: "command", command: $c}]}]}}' >"$1"
}

# ---------------------------------------------------------------------------
# R6.1: Hooks are listed from every source with a label (D14).
# ---------------------------------------------------------------------------
r61_home="$SCRATCH/r61-home"
r61_root="$SCRATCH/r61-root"
mkdir -p "$r61_home/.claude/plugins" "$r61_root/.claude" "$r61_root/.claude-plugin" "$r61_root/hooks"

echo '{"name": "srcplug", "version": "0.1.0"}' >"$r61_root/.claude-plugin/plugin.json"
hooks_json "$r61_root/.claude/settings.json"       PreToolUse Bash       "echo from-project"
hooks_json "$r61_root/.claude/settings.local.json" PreToolUse Edit       "echo from-project-local"
hooks_json "$r61_root/hooks/hooks.json"            PreToolUse 'Write|Edit' "echo from-plugin-source"

ext_path="$r61_home/.claude/plugins/cache/mkt/extplug/1.0.0"
off_path="$r61_home/.claude/plugins/cache/mkt/offplug/1.0.0"
mkdir -p "$ext_path/hooks" "$ext_path/.claude-plugin" "$off_path/hooks" "$off_path/.claude-plugin"
echo '{"name": "extplug", "version": "1.0.0"}' >"$ext_path/.claude-plugin/plugin.json"
echo '{"name": "offplug", "version": "1.0.0"}' >"$off_path/.claude-plugin/plugin.json"
hooks_json "$ext_path/hooks/hooks.json" PreToolUse Read "echo from-installed-plugin"
# A disabled installed plugin: D14 reads only enabled plugins' hooks.
hooks_json "$off_path/hooks/hooks.json" PreToolUse Read "echo from-disabled-plugin"

jq -n --arg ext "$ext_path" --arg off "$off_path" '{plugins: {
  "extplug@mkt": [{scope: "user", installPath: $ext, version: "1.0.0"}],
  "offplug@mkt": [{scope: "user", installPath: $off, version: "1.0.0"}]
}}' >"$r61_home/.claude/plugins/installed_plugins.json"

jq -n '{
  enabledPlugins: {"extplug@mkt": true, "offplug@mkt": false},
  hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "echo from-user"}]}]}
}' >"$r61_home/.claude/settings.json"

r61_expected='[
  {"source": "project",              "event": "PreToolUse", "matcher": "Bash",       "command": "echo from-project"},
  {"source": "project_local",        "event": "PreToolUse", "matcher": "Edit",       "command": "echo from-project-local"},
  {"source": "plugin_source",        "event": "PreToolUse", "matcher": "Write|Edit", "command": "echo from-plugin-source"},
  {"source": "user",                 "event": "PreToolUse", "matcher": "Bash",       "command": "echo from-user"},
  {"source": "plugin:extplug@mkt",   "event": "PreToolUse", "matcher": "Read",       "command": "echo from-installed-plugin"}
]'

name=r6_1_hooks_from_every_source_with_label
if run_ps "$name" "$r61_home" "$r61_root"; then
  check "$name" \
    '(.hooks | type == "array")
     and ([.hooks[] | {source, event, matcher, command}] | sort_by(.source, .command))
         == ($exp | sort_by(.source, .command))' \
    --argjson exp "$r61_expected"
fi

# ---------------------------------------------------------------------------
# R6.2: Planning artifacts are counted per kind (D15 B2).
# ---------------------------------------------------------------------------
r62_root="$SCRATCH/r62-root"
mkdir -p "$r62_root/specs/a" "$r62_root/specs/b" "$r62_root/specs/c"
echo '# Spec: a'               >"$r62_root/specs/a/spec.md"
echo '# Partition manifest: b' >"$r62_root/specs/b/partition-manifest.md"
echo '# Design: c'             >"$r62_root/specs/c/design.md"
echo '# Brief: c'              >"$r62_root/specs/c/brief.md"

name=r6_2_planning_artifacts_counted_per_kind
if run_ps "$name" "$HOME" "$r62_root"; then
  check "$name" \
    '.planning_artifacts.spec == 1
     and .planning_artifacts.partition_manifest == 1
     and .planning_artifacts.design == 1
     and .planning_artifacts.brief == 1
     and .planning_artifacts.insights == 0
     and .planning_artifacts.exist == true'
fi

# ---------------------------------------------------------------------------
# R6.5: Agents are listed with keys and analyzer flags (D15 D4, D6).
# ---------------------------------------------------------------------------
r65_root="$SCRATCH/r65-root"
mkdir -p "$r65_root/.claude-plugin" "$r65_root/agents" "$r65_root/.claude/agents" \
         "$r65_root/skills/foo" "$r65_root/.claude/skills/bar"
echo '{"name": "harness-ops", "version": "0.6.0"}' >"$r65_root/.claude-plugin/plugin.json"
fm() { printf -- '---\nname: %s\ndescription: %s\n---\n\n# %s\n' "$2" "$3" "$2" >"$1"; }
fm "$r65_root/agents/session-pattern-analyzer.md" session-pattern-analyzer "Analyzes session JSONL files"
fm "$r65_root/agents/qa-verifier.md"              qa-verifier              "Verifies QA results"
fm "$r65_root/.claude/agents/git-operator.md"     git-operator             "Commits and pushes"
fm "$r65_root/skills/foo/SKILL.md"                foo                      "The foo skill"
fm "$r65_root/.claude/skills/bar/SKILL.md"        bar                      "The bar skill"

name=r6_5_agents_and_skills_keyed_with_analyzer_flags
if run_ps "$name" "$HOME" "$r65_root"; then
  check "$name" \
    '([.agents[] | {key, analyzer, path}] | sort_by(.key)) == ([
        {key: "git-operator",                         analyzer: false, path: ".claude/agents/git-operator.md"},
        {key: "harness-ops:qa-verifier",              analyzer: false, path: "agents/qa-verifier.md"},
        {key: "harness-ops:session-pattern-analyzer", analyzer: true,  path: "agents/session-pattern-analyzer.md"}
      ] | sort_by(.key))
     and ([.skills[].key] | sort) == (["bar", "harness-ops:foo"] | sort)'
fi

# ---------------------------------------------------------------------------
# R6.6: Checker citations exclude check-harness itself (D15).
# ---------------------------------------------------------------------------
r66_root="$SCRATCH/r66-root"
mkdir -p "$r66_root/skills/check-harness" "$r66_root/skills/foo" "$r66_root/skills/bar/references"
printf -- '---\nname: check-harness\ndescription: x\n---\n\nSpawn with `capability:spawn-named-checker`.\n' \
  >"$r66_root/skills/check-harness/SKILL.md"
printf -- '---\nname: foo\ndescription: x\n---\n\nSpawn with `capability:spawn-named-checker`.\n' \
  >"$r66_root/skills/foo/SKILL.md"
printf -- '---\nname: bar\ndescription: x\n---\n\nThe bar skill.\n' >"$r66_root/skills/bar/SKILL.md"
printf -- '# r\n\nReview with `capability:spawn-inline-checker`.\n' >"$r66_root/skills/bar/references/r.md"

name=r6_6_checker_citations_exclude_check_harness
if run_ps "$name" "$HOME" "$r66_root"; then
  check "$name" \
    '(.checker_citations | type == "array")
     and (.checker_citations | sort) == (["skills/bar/references/r.md", "skills/foo/SKILL.md"] | sort)'
fi

# ---------------------------------------------------------------------------
# R6.7: Unattended ledgers are checked for all six limits (D18, D15 value parsing).
# ---------------------------------------------------------------------------
r67_root="$SCRATCH/r67-root"
mkdir -p "$r67_root/runs/a" "$r67_root/runs/b" "$r67_root/runs/c"

# autopilot_ledger KILLSWITCH RUN_STARTED_AT
autopilot_ledger() {
  cat <<EOF
# autopilot.md — nightly

## Config   (human-approved before the run starts)
- build_order: specs/build_order.md
- cadence_seconds: 240               # primary ScheduleWakeup delay
- per_tick_timeout_seconds: 900      # upper bound on a single unit
- wall_clock_cap_hours: 12
- max_ticks: 200                     # doubles as the cost cap
- consecutive_park_cap: 3
- crash_loop: { max: 3, window_minutes: 10 }
- killswitch_path: $1

## State   (the durable authority for halting)
- status: running                    # running | halted | done
- halt_reason: —
- run_started_at: $2
- tick_count: 4
- consecutive_parks: 0
- recent_crashes: []
EOF
}
autopilot_ledger "$r67_root/runs/a/STOP" "2026-10-30T01:00Z" >"$r67_root/runs/a/autopilot.md"
autopilot_ledger "<runDir>/STOP"          "2026-10-30T01:00Z" >"$r67_root/runs/b/autopilot.md"
# A copy of skills/autopilot/references/autopilot-template.md (placeholder run_started_at).
cat >"$r67_root/runs/c/autopilot.md" <<'EOF'
# autopilot.md — <run name>

> The durable run-control ledger for an unattended overnight build.

## Config   (human-approved before the run starts)
- build_order: <path/to/build_order.md>
- cadence_seconds: 240               # primary ScheduleWakeup delay; MUST be < per_tick_timeout
- per_tick_timeout_seconds: 900      # upper bound on a single ② unit (size to the slowest unit)
- wall_clock_cap_hours: 12
- max_ticks: 200                     # doubles as the cost cap (no token meter exists)
- consecutive_park_cap: 3
- crash_loop: { max: 3, window_minutes: 10 }
- killswitch_path: <runDir>/STOP

## State   (the durable authority for halting — re-derived at every tick entry)
- status: running                    # running | halted | done
- halt_reason: —
- run_started_at: <ts>
- tick_count: 0                      # incremented + flushed at tick ENTRY (before gated work)
- last_tick_started_at: —
- lease_renewed_at: —                # fresh ⇒ in-flight; stale past per_tick_timeout ⇒ hung
- last_tick_completed_at: —
- consecutive_parks: 0
- recent_crashes: []                 # timestamps, for the M-in-N crash-loop window
- backstop_cron_id: —                # CronDelete this on halt
EOF

name=r6_7_autopilot_ledgers_checked_for_six_limits
if run_ps "$name" "$HOME" "$r67_root"; then
  r67_ok=1
  if ! jq -e '
      ([.unattended.autopilot_files[] | {path, missing_limits}] | sort_by(.path)) == [
        {path: "runs/a/autopilot.md", missing_limits: []},
        {path: "runs/b/autopilot.md", missing_limits: ["killswitch_path"]}
      ]
      and .unattended.conforming == false
      and ([.warnings[] | select(contains("template-only autopilot.md") and contains("runs/c/autopilot.md"))] | length) >= 1
    ' "$SCRATCH/$name.out" >/dev/null 2>&1; then
    r67_ok=0
    fail "$name" "unexpected JSON: $(jq -c '{unattended, warnings}' "$SCRATCH/$name.out" 2>/dev/null | head -c 800)"
  fi
  if [ "$r67_ok" -eq 1 ] && ! grep -E '^warning: template-only autopilot\.md' "$SCRATCH/$name.err" | grep -q 'runs/c/autopilot.md'; then
    r67_ok=0
    fail "$name" "no stderr 'warning: template-only autopilot.md' naming runs/c/autopilot.md (stderr: $(head -c 400 "$SCRATCH/$name.err"))"
  fi
  [ "$r67_ok" -eq 1 ] && ok "$name"
fi

r67_empty="$SCRATCH/r67-empty-root"
mkdir -p "$r67_empty"
echo '# nothing unattended here' >"$r67_empty/README.md"
name=r6_7_no_autopilot_files_conforming_null
if run_ps "$name" "$HOME" "$r67_empty"; then
  check "$name" '(.unattended | has("conforming")) and .unattended.conforming == null'
fi

echo
if [ "$FAILS" -ne 0 ]; then
  echo "tt6_project_signals: $FAILS case(s) failed"
  exit 1
fi
echo "tt6_project_signals: all cases passed"
exit 0
