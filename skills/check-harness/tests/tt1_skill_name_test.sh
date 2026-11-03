#!/usr/bin/env bash
# TT1 — acceptance tests for R1 (skill-name normalisation, spec D3 + D2).
# Black box: drives skills/check-harness/scripts/skill_name.py through its CLI only.
# Run from the repo root: bash skills/check-harness/tests/tt1_skill_name_test.sh
set -u

SCRIPT="skills/check-harness/scripts/skill_name.py"
TAB=$'\t'

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
FIXTURE_HOME="$SCRATCH/home"
mkdir -p "$FIXTURE_HOME/.claude"

FAILS=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1: $2"; FAILS=$((FAILS + 1)); }

# run_case NAME EXPECTED_EXIT EXPECTED_STDOUT ARGS...
# Compares exit status and stdout exactly (EXPECTED_STDOUT is the lines joined by \n).
run_case() {
  local name="$1" want_exit="$2" want_out="$3"
  shift 3
  local out_file="$SCRATCH/$name.out" err_file="$SCRATCH/$name.err" got_exit
  # python3 itself exits 2 for a missing file, which would satisfy R1.4 vacuously.
  if [ ! -f "$SCRIPT" ]; then
    fail "$name" "$SCRIPT does not exist"
    return
  fi
  HOME="$FIXTURE_HOME" python3 "$SCRIPT" "$@" >"$out_file" 2>"$err_file"
  got_exit=$?
  local got_out
  got_out="$(cat "$out_file"; echo x)"
  got_out="${got_out%x}"
  if [ "$got_exit" -ne "$want_exit" ]; then
    fail "$name" "exit $got_exit, want $want_exit (stderr: $(head -c 300 "$err_file"))"
    return
  fi
  if [ "$got_out" != "$want_out" ]; then
    fail "$name" "stdout mismatch; got: $(printf '%q' "$got_out") want: $(printf '%q' "$want_out")"
    return
  fi
  ok "$name"
}

# R1.1: Old owners map to harness-ops — exactly two lines, exit 0.
run_case r1_1_old_owners_map_to_harness_ops 0 \
"harness:specify${TAB}harness-ops:specify
harness-session:qa${TAB}harness-ops:qa
" \
  harness:specify harness-session:qa

# R1.2: Renamed skills map to their current key, bare old names included, in argument order.
run_case r1_2_renames_including_bare_old_names 0 \
"harness:doc-drift${TAB}harness-ops:context-audit
harness-ops:deep-interview${TAB}harness-ops:requirements-interview
ralph${TAB}harness-ops:loop
deep-interview${TAB}harness-ops:requirements-interview
" \
  harness:doc-drift harness-ops:deep-interview ralph deep-interview

# R1.3: Owners are kept and renames never cross owners.
run_case r1_3_owners_kept_renames_never_cross_owners 0 \
"loop${TAB}loop
other-plugin:doc-drift${TAB}other-plugin:doc-drift
anthropic-skills:pdf${TAB}anthropic-skills:pdf
harness-ops:loop${TAB}harness-ops:loop
" \
  loop other-plugin:doc-drift anthropic-skills:pdf harness-ops:loop

# R1.4: No arguments is a usage error — exit 2, empty stdout.
run_case r1_4_no_arguments_is_usage_error 2 ""

if [ "$FAILS" -ne 0 ]; then
  echo "tt1_skill_name: $FAILS case(s) failed"
  exit 1
fi
echo "tt1_skill_name: all cases passed"
exit 0
