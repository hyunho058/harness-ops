#!/bin/bash
# test-block-main-push.sh — behaviour table for .claude/hooks/block-main-push.sh
#
# The hook decides whether a command writes to the protected branch. That is a
# parsing job with a lot of edge cases (refspecs, --delete, colon-deletes, HEAD,
# --all/--mirror, git global options, flags that swallow their value), and the
# over-blocking bugs in the hook's history were all found in production rather
# than here. This table is the mechanical check that was missing.
#
# Run: scripts/test-block-main-push.sh      (exit 0 = every case behaves)
#
# SELF-CONTAINED BY DESIGN. The hook reads the checked-out branch from its own
# cwd, so an earlier version of this file used the harness-ops checkout as the
# "HEAD is main" fixture — and then failed 4 cases whenever you ran it from a
# feature branch, which is most of the time. A test that only passes on one
# branch gets ignored, so both fixtures are scratch repos built here.
#
# HOOK is overridable so an older copy can be run against this same table.

set -u

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
HOOK="${HOOK:-$REPO/.claude/hooks/block-main-push.sh}"
pass=0; fail=0

WORK=$(mktemp -d "${TMPDIR:-/tmp}/block-main-push-test.XXXXXX")
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# fixture <dir> <branch> — a throwaway repo with <branch> checked out
fixture() {
  local dir="$WORK/$1" br="$2"
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    git init -q -b "$br" . 2>/dev/null || { git init -q .; git checkout -q -b "$br"; }
    git config user.email test@example.invalid
    git config user.name test
    echo x > f
    git add f
    git commit -qm init
  )
  printf '%s' "$dir"
}

ON_MAIN=$(fixture on-main main)
ON_FEAT=$(fixture on-feat feat/x)

# sanity: the fixtures really are on the branches the table assumes
[ "$(git -C "$ON_MAIN" rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "fixture ON_MAIN is not on main"; exit 1; }
[ "$(git -C "$ON_FEAT" rev-parse --abbrev-ref HEAD)" = "feat/x" ] || { echo "fixture ON_FEAT is not on feat/x"; exit 1; }

# run <expect> <cwd> <command> [PATH override]
run() {
  local expect="$1" cwd="$2" cmd="$3" path="${4-KEEP}" rc got json label=""
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if [ "$path" = KEEP ]; then
    ( cd "$cwd" && printf '%s' "$json" | "$HOOK" >/dev/null 2>&1 )
  else
    label="(PATH stripped) "
    ( cd "$cwd" && printf '%s' "$json" | PATH="$path" "$HOOK" >/dev/null 2>&1 )
  fi
  rc=$?
  got=ALLOW; [ "$rc" -eq 2 ] && got=BLOCK
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1)); printf '  ok   %-5s %s%s\n' "$got" "$label" "$cmd"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s  %s%s\n' "$expect" "$got" "$label" "$cmd"
  fi
}

echo "== HEAD is main =="
run BLOCK "$ON_MAIN" 'git push'
run BLOCK "$ON_MAIN" 'git push origin'
run BLOCK "$ON_MAIN" 'git push origin main'
run BLOCK "$ON_MAIN" 'git push origin HEAD'
run BLOCK "$ON_MAIN" 'git push origin HEAD:main'
run BLOCK "$ON_MAIN" 'git push origin feat/x:main'
run BLOCK "$ON_MAIN" 'git push origin refs/heads/main'
run BLOCK "$ON_MAIN" 'git push origin +main'
run BLOCK "$ON_MAIN" 'git push --force origin main'
run BLOCK "$ON_MAIN" 'git push -f origin main'
run BLOCK "$ON_MAIN" 'git push origin :main'
run BLOCK "$ON_MAIN" 'git push origin --delete main'
run BLOCK "$ON_MAIN" 'git push origin -d main'
run BLOCK "$ON_MAIN" 'git push --all origin'
run BLOCK "$ON_MAIN" 'git push --mirror origin'
run BLOCK "$ON_MAIN" 'git push -u origin main'

echo "== HEAD is main, but the push does NOT target main =="
run ALLOW "$ON_MAIN" 'git push origin --delete feat/some-merged-branch'
run ALLOW "$ON_MAIN" 'git push origin -d feat/x'
run ALLOW "$ON_MAIN" 'git push origin feat/x'
run ALLOW "$ON_MAIN" 'git push -u origin feat/x'
run ALLOW "$ON_MAIN" 'git push origin main:feat/x'
run ALLOW "$ON_MAIN" 'git push origin :feat/x'
run ALLOW "$ON_MAIN" 'git push origin -o ci.skip feat/x'
run ALLOW "$ON_MAIN" 'git push --force-with-lease origin feat/x'
run ALLOW "$ON_MAIN" 'git push origin refs/heads/feat/x'

echo "== the word appears in a FILENAME, not as the subcommand =="
# Regression: matching "push" anywhere made the guard block reading its own
# source and its own test file whenever HEAD was main.
run ALLOW "$ON_MAIN" 'git show HEAD:.claude/hooks/block-main-push.sh'
run ALLOW "$ON_MAIN" 'git diff scripts/test-block-main-push.sh'
run ALLOW "$ON_MAIN" 'git log --oneline -- scripts/test-block-main-push.sh'
run ALLOW "$ON_MAIN" 'git add .claude/hooks/block-main-push.sh'
run ALLOW "$ON_MAIN" 'cat .claude/hooks/block-main-push.sh'
run ALLOW "$ON_MAIN" 'git log --grep=push --oneline'

echo "== git global options before the subcommand =="
run BLOCK "$ON_MAIN" 'git -C /tmp/repo push origin main'
run ALLOW "$ON_MAIN" 'git -C /tmp/repo push origin feat/x'
run BLOCK "$ON_MAIN" 'git -c user.name=x push origin main'

echo "== not a push at all =="
run ALLOW "$ON_MAIN" 'git status --short'
run ALLOW "$ON_MAIN" 'git log --oneline -5'
run ALLOW "$ON_MAIN" 'ls -la'
run ALLOW "$ON_MAIN" 'git pull --ff-only'

echo "== multi-command lines =="
run ALLOW "$ON_MAIN" 'git add -A && git commit -m wip && git push origin feat/x'
run BLOCK "$ON_MAIN" 'git push origin feat/x && git push origin main'
run BLOCK "$ON_MAIN" 'echo hi; git push origin main'

echo "== HEAD is a feature branch =="
run ALLOW "$ON_FEAT" 'git push'
run ALLOW "$ON_FEAT" 'git push origin'
run ALLOW "$ON_FEAT" 'git push origin HEAD'
run ALLOW "$ON_FEAT" 'git push -u origin feat/x'
run BLOCK "$ON_FEAT" 'git push origin main'
run BLOCK "$ON_FEAT" 'git push origin HEAD:main'
run BLOCK "$ON_FEAT" 'git push origin --delete main'

echo "== a broken PATH must not make the guard fail OPEN =="
# Regression: before the hook normalised PATH, a PATH without `grep` made every
# check silently succeed and every push was allowed, protected branch included.
EMPTYBIN="$WORK/empty-bin"
mkdir -p "$EMPTYBIN"
run BLOCK "$ON_MAIN" 'git push origin main'          ""
run BLOCK "$ON_MAIN" 'git push origin main'          "$EMPTYBIN"
run BLOCK "$ON_MAIN" 'git push'                      "/nonexistent"
run ALLOW "$ON_MAIN" 'git push origin feat/x'        ""
run ALLOW "$ON_MAIN" 'git push origin --delete feat/x' "$EMPTYBIN"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
