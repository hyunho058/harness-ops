#!/usr/bin/env bash
# TT5 — acceptance tests for R5 (project-root discovery, spec D12 + D2).
# Black box: drives skills/check-harness/scripts/project_root.py through its CLI only.
# Run from the repo root: bash skills/check-harness/tests/tt5_project_root_test.sh
set -u

SCRIPT="skills/check-harness/scripts/project_root.py"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
# D2: every printed path is resolved, so compare against the realpath spelling.
SCRATCH="$(realpath "$SCRATCH")"

FAILS=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1: $2"; FAILS=$((FAILS + 1)); }

# Precondition: the fixtures must not sit inside any git work tree or below a
# .claude/ or CLAUDE.md we did not create, or the walk-up cases are meaningless.
if git -C "$SCRATCH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL - precondition: scratch dir $SCRATCH is inside a git work tree"
  exit 1
fi
p="$SCRATCH"
while [ "$p" != "/" ]; do
  p="$(dirname "$p")"
  if [ -e "$p/.claude" ] || [ -e "$p/CLAUDE.md" ]; then
    echo "FAIL - precondition: ancestor $p of the scratch dir has .claude/ or CLAUDE.md"
    exit 1
  fi
done

# run_root CASE HOME_DIR ARGS... -> sets GOT_EXIT, GOT_OUT, GOT_ERR
run_root() {
  local name="$1" home="$2"
  shift 2
  HOME="$home" python3 "$SCRIPT" "$@" >"$SCRATCH/$name.out" 2>"$SCRATCH/$name.err"
  GOT_EXIT=$?
  GOT_OUT="$(cat "$SCRATCH/$name.out"; echo x)"
  GOT_OUT="${GOT_OUT%x}"
  GOT_ERR="$(cat "$SCRATCH/$name.err")"
}

# expect_found CASE WANT_PATH: exit 0 and stdout is exactly WANT_PATH (one line).
expect_found() {
  local name="$1" want="$2"
  if [ "$GOT_EXIT" -ne 0 ]; then
    fail "$name" "exit $GOT_EXIT, want 0 (stderr: $(printf '%s' "$GOT_ERR" | head -c 300))"
  elif [ "$GOT_OUT" != "$want" ] && [ "$GOT_OUT" != "$want"$'\n' ]; then
    fail "$name" "stdout $(printf '%q' "$GOT_OUT"), want $(printf '%q' "$want")"
  else
    ok "$name"
  fi
}

# expect_not_found CASE: exit 3, empty stdout, stderr starts with "no project root:".
expect_not_found() {
  local name="$1"
  if [ "$GOT_EXIT" -ne 3 ]; then
    fail "$name" "exit $GOT_EXIT, want 3 (stdout: $(printf '%q' "$GOT_OUT"))"
  elif [ -n "$GOT_OUT" ]; then
    fail "$name" "stdout not empty: $(printf '%q' "$GOT_OUT")"
  elif [ "${GOT_ERR#no project root:}" = "$GOT_ERR" ]; then
    fail "$name" "stderr does not start with 'no project root:': $(printf '%q' "$(printf '%s' "$GOT_ERR" | head -c 300)")"
  else
    ok "$name"
  fi
}

# R5.1: Inside git, the root is the toplevel.
T1="$SCRATCH/r5_1"
mkdir -p "$T1/home" "$T1/repo/a/b"
git -C "$T1/repo" init -q
run_root r5_1_inside_git_root_is_toplevel "$T1/home" "$T1/repo/a/b"
expect_found r5_1_inside_git_root_is_toplevel "$T1/repo"

# R5.2: Outside git, walk up to a CLAUDE.md.
T2="$SCRATCH/r5_2"
mkdir -p "$T2/home" "$T2/proj/sub"
: >"$T2/proj/CLAUDE.md"
run_root r5_2_outside_git_walks_up_to_claude_md "$T2/home" "$T2/proj/sub"
expect_found r5_2_outside_git_walks_up_to_claude_md "$T2/proj"

# R5.3: $HOME and its ancestors never qualify.
T3="$SCRATCH/r5_3"
mkdir -p "$T3/home/.claude" "$T3/home/notes"
run_root r5_3_home_and_ancestors_never_qualify "$T3/home" "$T3/home/notes"
expect_not_found r5_3_home_and_ancestors_never_qualify

# R5.4: A git toplevel equal to $HOME is not a project.
T4="$SCRATCH/r5_4"
mkdir -p "$T4/home/x"
git -C "$T4/home" init -q
run_root r5_4_git_toplevel_equal_to_home_is_not_a_project "$T4/home" "$T4/home/x"
expect_not_found r5_4_git_toplevel_equal_to_home_is_not_a_project

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed"
  exit 1
fi
echo "all cases passed"
