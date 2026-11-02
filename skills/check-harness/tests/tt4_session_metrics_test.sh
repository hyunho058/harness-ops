#!/usr/bin/env bash
# TT4 — acceptance tests for R4 (session_metrics.py) of specs/check-harness-refresh/spec.md.
# Decisions: D9 (metric definitions), D3 (key normalisation, role match), D2 (CLI contract).
# Black-box: only runs `python3 skills/check-harness/scripts/session_metrics.py …`.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$REPO_ROOT" || exit 1
SCRIPT="skills/check-harness/scripts/session_metrics.py"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export PYTHONDONTWRITEBYTECODE=1

FAILS=0
ok()   { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; shift; for l in "$@"; do printf '       %s\n' "$l"; done; FAILS=$((FAILS + 1)); }

# --- fixture builders -------------------------------------------------------
# ts MINUTE [SECOND] -> ISO-8601 timestamp on a fixed day
ts() { printf '2026-10-01T10:%02d:%02d.000Z' "$1" "${2:-0}"; }

# asst FILE MINUTE MSG_ID TOOL_NAME INPUT_JSON — one tool_use per line
asst() {
  jq -cn --arg ts "$(ts "$2")" --arg id "$3" --arg name "$4" --argjson input "$5" \
    '{type:"assistant",timestamp:$ts,message:{id:$id,role:"assistant",
      content:[{type:"tool_use",id:("toolu_" + $id + "_" + $name),name:$name,input:$input}]}}' >> "$1"
}

# user FILE MINUTE CONTENT
user() {
  jq -cn --arg ts "$(ts "$2")" --arg c "$3" \
    '{type:"user",timestamp:$ts,message:{role:"user",content:$c}}' >> "$1"
}

# run_metrics OUT_PREFIX ARGS… — stdout to $OUT_PREFIX.out, stderr to .err, status to .rc
run_metrics() {
  local pfx=$1; shift
  python3 "$SCRIPT" "$@" > "$pfx.out" 2> "$pfx.err"
  echo $? > "$pfx.rc"
}

# check NAME PREFIX JQ_EXPR — exit 0, stdout parses, expression true
check() {
  local name=$1 pfx=$2 expr=$3 rc
  rc=$(cat "$pfx.rc")
  if [ "$rc" != 0 ]; then
    fail "$name" "exit $rc" "stderr: $(head -c 400 "$pfx.err")"
    return
  fi
  if jq -e "$expr" "$pfx.out" > /dev/null 2>&1; then
    ok "$name"
  else
    fail "$name" "expected: $expr" "stdout: $(head -c 600 "$pfx.out")"
  fi
}

# --- R4.1: parallel spawns are counted per message id -----------------------
D="$TMP/r41"; mkdir -p "$D"; F="$D/s.jsonl"
user "$F" 0 "start"
asst "$F" 1 msg_par01 Agent '{"description":"a","prompt":"p","subagent_type":"general-purpose"}'
asst "$F" 1 msg_par01 Agent '{"description":"b","prompt":"p","subagent_type":"general-purpose"}'
asst "$F" 3 msg_bg0001 Agent '{"description":"c","prompt":"p","subagent_type":"general-purpose","run_in_background":true}'
printf '%s\n' "$F" > "$D/list"
run_metrics "$D/r" --files-from "$D/list"
check "R4.1 parallel_count=1 background_flag_count=1" "$D/r" \
  '.metrics.parallel_count == 1 and .metrics.background_flag_count == 1'

# --- R4.2: typed slash commands, prompt text never emitted ------------------
D="$TMP/r42"; mkdir -p "$D"; F="$D/s.jsonl"
user "$F" 0 '<command-name>/harness-ops:specify</command-name><command-args>SECRET-PROMPT-TEXT</command-args>'
asst "$F" 2 msg_r42a Read '{"file_path":"/w/a.md"}'
printf '%s\n' "$F" > "$D/list"
run_metrics "$D/r" --files-from "$D/list"
check "R4.2 commands_invoked harness-ops:specify=1, plan_first_ratio=1.0" "$D/r" \
  '.commands_invoked["harness-ops:specify"] == 1 and .metrics.plan_first_ratio == 1'
if [ "$(cat "$D/r.rc")" != 0 ] || ! jq -e . "$D/r.out" > /dev/null 2>&1; then
  fail "R4.2 SECRET-PROMPT-TEXT absent from stdout and stderr" "script did not run cleanly (exit $(cat "$D/r.rc"))"
elif grep -q 'SECRET-PROMPT-TEXT' "$D/r.out" "$D/r.err"; then
  fail "R4.2 SECRET-PROMPT-TEXT absent from stdout and stderr" "found in output"
else
  ok "R4.2 SECRET-PROMPT-TEXT absent from stdout and stderr"
fi

# --- R4.3: plan-first uses role match and plan mode -------------------------
D="$TMP/r43"; mkdir -p "$D"
asst "$D/a.jsonl" 0 msg_r43a Skill '{"skill":"harness:specify"}'
asst "$D/a.jsonl" 1 msg_r43b Read '{"file_path":"/w/a.md"}'
asst "$D/b.jsonl" 0 msg_r43c EnterPlanMode '{}'
asst "$D/b.jsonl" 1 msg_r43d Read '{"file_path":"/w/b.md"}'
asst "$D/c.jsonl" 0 msg_r43e Skill '{"skill":"loop"}'
asst "$D/c.jsonl" 1 msg_r43f Read '{"file_path":"/w/c.md"}'
printf '%s\n' "$D/a.jsonl" "$D/b.jsonl" "$D/c.jsonl" > "$D/list"
run_metrics "$D/r" --files-from "$D/list"
check "R4.3 plan_first_ratio=0.67" "$D/r" '.metrics.plan_first_ratio == 0.67'
check "R4.3 skills_invoked has harness-ops:specify and loop" "$D/r" \
  '(.skills_invoked | has("harness-ops:specify")) and (.skills_invoked | has("loop"))'

# --- R4.4: handoff counts ledger and memory writes in long sessions ---------
D="$TMP/r44"; mkdir -p "$D"
asst "$D/a.jsonl" 0  msg_r44a Read  '{"file_path":"/w/specs/x/spec.md"}'
asst "$D/a.jsonl" 30 msg_r44b Write '{"file_path":"/w/specs/x/build_order.md","content":"x"}'
asst "$D/b.jsonl" 0  msg_r44c Read  '{"file_path":"/w/src/a.py"}'
asst "$D/b.jsonl" 30 msg_r44d Edit  '{"file_path":"/w/src/a.py","old_string":"a","new_string":"b"}'
asst "$D/c.jsonl" 0  msg_r44e Read  '{"file_path":"/w/src/c.py"}'
asst "$D/c.jsonl" 5  msg_r44f Edit  '{"file_path":"/u/.claude/projects/p/memory/MEMORY.md","old_string":"a","new_string":"b"}'
printf '%s\n' "$D/a.jsonl" "$D/b.jsonl" "$D/c.jsonl" > "$D/list"
run_metrics "$D/r" --long-session-min 20 --files-from "$D/list"
check "R4.4 long_sessions=2 handoff_ratio=0.5" "$D/r" \
  '.long_sessions == 2 and .metrics.handoff_ratio == 0.5'

# --- R4.5: completion check -------------------------------------------------
D="$TMP/r45"; mkdir -p "$D"
# A: 10 tool calls, the 9th a Bash run-tests.sh
for i in 1 2 3 4 5 6 7 8; do
  asst "$D/a.jsonl" "$i" "msg_r45a$i" Read "{\"file_path\":\"/w/f$i.md\"}"
done
asst "$D/a.jsonl" 9  msg_r45a9  Bash '{"command":"bash skills/coherence-audit/scripts/run-tests.sh"}'
asst "$D/a.jsonl" 10 msg_r45a10 Read '{"file_path":"/w/f10.md"}'
# B: Skill harness-ops:loop as its first call
asst "$D/b.jsonl" 0 msg_r45b1 Skill '{"skill":"harness-ops:loop"}'
asst "$D/b.jsonl" 1 msg_r45b2 Read  '{"file_path":"/w/b1.md"}'
asst "$D/b.jsonl" 2 msg_r45b3 Read  '{"file_path":"/w/b2.md"}'
# C: built-in Skill loop, and the shell builtin `test` as its last call
asst "$D/c.jsonl" 0 msg_r45c1 Skill '{"skill":"loop"}'
asst "$D/c.jsonl" 1 msg_r45c2 Read  '{"file_path":"/w/c1.md"}'
asst "$D/c.jsonl" 2 msg_r45c3 Bash  '{"command":"test -f x"}'
printf '%s\n' "$D/a.jsonl" "$D/b.jsonl" "$D/c.jsonl" > "$D/list"
run_metrics "$D/r" --files-from "$D/list"
check "R4.5 completion_check_ratio=0.67" "$D/r" '.metrics.completion_check_ratio == 0.67'

# --- R4.6: learning writes are counted per session --------------------------
D="$TMP/r46"; mkdir -p "$D"
asst "$D/a.jsonl" 0 msg_r46a Read  '{"file_path":"/w/README.md"}'
asst "$D/a.jsonl" 1 msg_r46b Edit  '{"file_path":"/w/CLAUDE.md","old_string":"a","new_string":"b"}'
asst "$D/b.jsonl" 0 msg_r46c Read  '{"file_path":"/w/README.md"}'
asst "$D/b.jsonl" 1 msg_r46d Write '{"file_path":"/w/.claude/rules/style.md","content":"x"}'
asst "$D/c.jsonl" 0 msg_r46e Read  '{"file_path":"/w/README.md"}'
asst "$D/c.jsonl" 1 msg_r46f Edit  '{"file_path":"/w/src/main.py","old_string":"a","new_string":"b"}'
printf '%s\n' "$D/a.jsonl" "$D/b.jsonl" "$D/c.jsonl" > "$D/list"
run_metrics "$D/r" --files-from "$D/list"
check "R4.6 learning_write_sessions=2" "$D/r" '.metrics.learning_write_sessions == 2'

# --- R4.7: empty denominators, bad lines, unreadable files ------------------
D="$TMP/r47"; mkdir -p "$D"; F="$D/s.jsonl"
asst "$F" 0 msg_r47a Read '{"file_path":"/w/a.md"}'
printf '%s\n' '{"type":"assistant", this is not json' >> "$F"
asst "$F" 5 msg_r47b Read '{"file_path":"/w/b.md"}'
printf '%s\n' "$F" "$D/does-not-exist.jsonl" \
  | python3 "$SCRIPT" --files-from - > "$D/r.out" 2> "$D/r.err"
echo $? > "$D/r.rc"
check "R4.7 exit 0, sessions_analyzed=1, handoff_ratio=null" "$D/r" \
  '.sessions_analyzed == 1 and (.metrics | has("handoff_ratio")) and .metrics.handoff_ratio == null'
if grep -q '^warning: skipped 1 unparseable line(s)' "$D/r.err"; then
  ok "R4.7 stderr warning: skipped 1 unparseable line(s)"
else
  fail "R4.7 stderr warning: skipped 1 unparseable line(s)" "stderr: $(head -c 400 "$D/r.err")"
fi
if grep -q '^warning: unreadable session file' "$D/r.err"; then
  ok "R4.7 stderr warning: unreadable session file"
else
  fail "R4.7 stderr warning: unreadable session file" "stderr: $(head -c 400 "$D/r.err")"
fi
check "R4.7 both warnings copied into the JSON warnings array" "$D/r" \
  '(.warnings | map(select(test("^(warning: )?skipped 1 unparseable line\\(s\\)"))) | length >= 1)
   and (.warnings | map(select(test("^(warning: )?unreadable session file"))) | length >= 1)'

# --- R4.8: 3-gram share and automation opportunities shapes ---------------
D="$TMP/r48"; mkdir -p "$D"; F="$D/s.jsonl"
m=0
for rep in 1 2 3 4; do
  asst "$F" "$m" "msg_r48r$rep" Read '{"file_path":"/w/a.py"}'; m=$((m + 1))
  asst "$F" "$m" "msg_r48e$rep" Edit '{"file_path":"/w/a.py","old_string":"a","new_string":"b"}'; m=$((m + 1))
  asst "$F" "$m" "msg_r48b$rep" Bash '{"command":"ls"}'; m=$((m + 1))
done
printf '%s\n' "$F" > "$D/list"
run_metrics "$D/r" --files-from "$D/list"
check "R4.8 top_3gram_share=1.0" "$D/r" '.metrics.top_3gram_share == 1'
check "R4.8 automation_opportunities: <=5 objects with exactly {pattern,count}, first Read→Edit→Bash" "$D/r" \
  '(.automation_opportunities | type == "array")
   and (.automation_opportunities | length >= 1 and length <= 5)
   and all(.automation_opportunities[]; type == "object" and (keys == ["count","pattern"]))
   and .automation_opportunities[0].pattern == "Read→Edit→Bash"'

# --- R4.9: params lines are skipped as input and echoed ---------------------
D="$TMP/r49"; mkdir -p "$D"; F="$D/s.jsonl"
asst "$F" 0 msg_r49a Read '{"file_path":"/w/a.md"}'
asst "$F" 1 msg_r49b Read '{"file_path":"/w/b.md"}'
{
  printf '%s\n' '# params {"scope": "project", "project_dir": "/x", "days": 30}'
  printf '%s\n' "$F"
} > "$D/list"
run_metrics "$D/r" --files-from "$D/list"
check "R4.9 sessions_analyzed=1, params.session_files echoed, long_session_min=20" "$D/r" \
  '.sessions_analyzed == 1
   and .params.session_files == {"scope":"project","project_dir":"/x","days":30}
   and .params.long_session_min == 20'

if [ "$FAILS" -gt 0 ]; then
  printf '%d case(s) failed\n' "$FAILS"
  exit 1
fi
printf 'all cases passed\n'
exit 0
