#!/usr/bin/env bash
# TT6 — acceptance tests for R6.3, R6.4, R6.8 (git-dated project signals; spec D15, D2).
# Black box: drives skills/check-harness/scripts/project_signals.py through its CLI only.
# Every repo here is a scratch repo under mktemp; commit dates are set relative to --as-of-ms.
# Run from the repo root: bash skills/check-harness/tests/tt6_project_signals_git_test.sh
set -u

SCRIPT="skills/check-harness/scripts/project_signals.py"
# Never leave __pycache__ in the repo.
export PYTHONDONTWRITEBYTECODE=1

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
# Keep git (ours and the script's) from discovering a repository above the fixtures.
export GIT_CEILING_DIRECTORIES="$SCRATCH"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$SCRATCH/home/.claude"
export HOME="$SCRATCH/home"

# --as-of-ms: 2026-10-31T12:00:00Z.
T_S=1793448000
T_MS="${T_S}000"
DAY=86400

FAILS=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1: $2"; FAILS=$((FAILS + 1)); }

# new_repo DIR
new_repo() {
  mkdir -p "$1"
  git -c init.defaultBranch=main init -q "$1"
}

# commit_at REPO EPOCH MESSAGE PATH... — stages the given paths and commits them at EPOCH.
commit_at() {
  local repo="$1" epoch="$2" msg="$3"
  shift 3
  git -C "$repo" add -- "$@"
  GIT_AUTHOR_DATE="@$epoch +0000" GIT_COMMITTER_DATE="@$epoch +0000" \
    git -C "$repo" -c user.name=tt6 -c user.email=tt6@example.invalid -c commit.gpgsign=false \
    commit -q -m "$msg"
}

# run_ps NAME ROOT [EXTRA_ARGS...]
# Leaves stdout in $SCRATCH/NAME.out, stderr in $SCRATCH/NAME.err.
# Returns 0 only when the script exists, exits 0 and prints a JSON object.
run_ps() {
  local name="$1" root="$2"
  shift 2
  local out="$SCRATCH/$name.out" err="$SCRATCH/$name.err" rc
  if [ ! -f "$SCRIPT" ]; then
    fail "$name" "$SCRIPT does not exist"
    return 1
  fi
  python3 "$SCRIPT" --project-root "$root" "$@" >"$out" 2>"$err"
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

# check NAME JQ_EXPR — passes when the expression is true on NAME's stdout.
check() {
  local name="$1" expr="$2"
  if jq -e "$expr" "$SCRATCH/$name.out" >/dev/null 2>&1; then
    ok "$name"
  else
    fail "$name" "expected: $expr; got: $(jq -c '{lessons, compounding, warnings}' "$SCRATCH/$name.out" 2>/dev/null | head -c 800)"
  fi
}

real_lesson_ledger() {
  cat <<'EOF'
# loop.md — x

## Gates
- gate1: bash scripts/test.sh

## Lessons

### L1 — run the lint before declaring done
- cause: gate-fail
- source: human-approved
- form: gate1-command
- status: active
- check: bash scripts/lint.sh
- note: the lint was skipped once; this makes it a gate
EOF
}

lesson_skeleton() {
  cat <<'EOF'
# loop.md — <task>

## Lessons

### <id> — <short title>
- cause: escalation | gate-fail
- source: human-approved | auto-unattended
- form: gate1-command | gate3-item | context
- status: active | needs-review | retired
- check: <hardened Gate-1 command | Gate-3 item text | "—" for context>
- note: <what went wrong, what this prevents — one line>
EOF
}

# ---------------------------------------------------------------------------
# R6.3: Recent real lessons count; stubs and templates do not (D15 ledger search, E1).
# build_r63 DIR LEDGER_AGE_DAYS
# ---------------------------------------------------------------------------
build_r63() {
  local repo="$1" age="$2"
  new_repo "$repo"
  mkdir -p "$repo/specs/x" "$repo/.claude/skills"
  real_lesson_ledger >"$repo/specs/x/loop.md"
  commit_at "$repo" $((T_S - age * DAY)) "add x loop contract" specs/x/loop.md
  lesson_skeleton >"$repo/.claude/skills/loop.md"
  commit_at "$repo" $((T_S - 3600)) "add loop skill stub" .claude/skills/loop.md
}

build_r63 "$SCRATCH/r63-recent" 10
name=r6_3_recent_real_lesson_counts_stub_ignored
if run_ps "$name" "$SCRATCH/r63-recent" --as-of-ms "$T_MS"; then
  check "$name" '.lessons.updated_30d == true and .lessons.files == ["specs/x/loop.md"]'
fi

build_r63 "$SCRATCH/r63-old" 40
name=r6_3_lesson_older_than_30d_not_updated
if run_ps "$name" "$SCRATCH/r63-old" --as-of-ms "$T_MS"; then
  check "$name" '.lessons.updated_30d == false'
fi

# ---------------------------------------------------------------------------
# R6.4: Hardened lessons are counted by exact added lines (D15 E3).
# ---------------------------------------------------------------------------
r64="$SCRATCH/r64"
new_repo "$r64"
mkdir -p "$r64/specs/x" "$r64/specs/y"
cat >"$r64/specs/x/loop.md" <<'EOF'
# loop.md — x

## Lessons

### L1 — run the lint
- cause: gate-fail
- source: human-approved
- form: gate1-command
- status: active
- check: bash scripts/lint.sh
- note: the lint was skipped once
EOF
commit_at "$r64" $((T_S - 50 * DAY)) "x: first lesson" specs/x/loop.md
cat >>"$r64/specs/x/loop.md" <<'EOF'

### L2 — check the error copy
- cause: escalation
- source: human-approved
- form: gate3-item
- status: active
- check: every error message names the file it failed on
- note: an error said "failed" with no file
EOF
commit_at "$r64" $((T_S - 20 * DAY)) "x: second lesson" specs/x/loop.md
cat >"$r64/specs/y/loop.md" <<'EOF'
# loop.md — y

## Lessons

### <id> — <short title>
- cause: escalation | gate-fail
- source: human-approved | auto-unattended
- form: gate1-command | gate3-item | context
- status: active | needs-review | retired
- check: <hardened Gate-1 command | Gate-3 item text | "—" for context>
- note: <what went wrong, what this prevents — one line>
EOF
commit_at "$r64" $((T_S - 30 * DAY)) "y: lesson skeleton" specs/y/loop.md

name=r6_4_hardened_lessons_counted_by_exact_added_lines
if run_ps "$name" "$r64" --as-of-ms "$T_MS"; then
  check "$name" '.lessons.hardened_added_90d == 2'
fi

# ---------------------------------------------------------------------------
# R6.8: Compounding counts agents, and git faults null the git fields (D15, D2).
# ---------------------------------------------------------------------------
r68="$SCRATCH/r68-git"
new_repo "$r68"
mkdir -p "$r68/.claude/agents"
printf -- '---\nname: new\ndescription: A newly added agent\n---\n\n# new\n' >"$r68/.claude/agents/new.md"
commit_at "$r68" $((T_S - 20 * DAY)) "add new agent" .claude/agents/new.md

name=r6_8_agents_added_90d_counted
if run_ps "$name" "$r68" --as-of-ms "$T_MS"; then
  check "$name" '.compounding.agents_added_90d == 1'
fi

r68_nogit="$SCRATCH/r68-nogit"
cp -R "$r68" "$r68_nogit"
rm -rf "$r68_nogit/.git"
name=r6_8_no_git_nulls_git_fields_with_warning
if run_ps "$name" "$r68_nogit" --as-of-ms "$T_MS"; then
  r68_ok=1
  if ! jq -e '
      (.compounding | has("claude_md_updated_30d") and has("agents_added_90d"))
      and .compounding.claude_md_updated_30d == null
      and .compounding.agents_added_90d == null
      and ([.warnings[] | select(contains("git unavailable"))] | length) >= 1
    ' "$SCRATCH/$name.out" >/dev/null 2>&1; then
    r68_ok=0
    fail "$name" "unexpected JSON: $(jq -c '{compounding, warnings}' "$SCRATCH/$name.out" 2>/dev/null | head -c 800)"
  fi
  if [ "$r68_ok" -eq 1 ] && ! grep -qE '^warning: git unavailable' "$SCRATCH/$name.err"; then
    r68_ok=0
    fail "$name" "no stderr line starting 'warning: git unavailable' (stderr: $(head -c 400 "$SCRATCH/$name.err"))"
  fi
  [ "$r68_ok" -eq 1 ] && ok "$name"
fi

echo
if [ "$FAILS" -ne 0 ]; then
  echo "tt6_project_signals_git: $FAILS case(s) failed"
  exit 1
fi
echo "tt6_project_signals_git: all cases passed"
exit 0
