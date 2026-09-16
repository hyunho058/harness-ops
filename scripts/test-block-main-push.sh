#!/bin/bash
# test-block-main-push.sh — behaviour table for .claude/hooks/block-main-push.sh
#
# The hook decides whether a command writes to the protected branch. That is a
# parsing job with a lot of edge cases (refspecs, --delete, colon-deletes, HEAD,
# --all/--mirror, flags that swallow their value), and the two over-blocking bugs
# in the hook's history were both found in production rather than here. This
# table is the mechanical check that was missing.
#
# Run: scripts/test-block-main-push.sh      (exit 0 = every case behaves)
#
# NOTE: run it from a checkout whose HEAD is `main`; the first block asserts the
# behaviour seen from the protected branch. It creates its own scratch repo for
# the feature-branch cases.

set -u
REPO=$(cd "$(dirname "$0")/.." && pwd -P)
# HOOK is overridable so an older copy can be run against this same table.
HOOK="${HOOK:-$REPO/.claude/hooks/block-main-push.sh}"
pass=0; fail=0

run() {  # run <expect> <cwd> <command>
  local expect="$1" cwd="$2" cmd="$3" rc
  local json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd")
  ( cd "$cwd" && printf '%s' "$json" | "$HOOK" >/dev/null 2>&1 )
  rc=$?
  local got=ALLOW
  [ "$rc" -eq 2 ] && got=BLOCK
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1)); printf '  ok   %-5s %s\n' "$got" "$cmd"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s  %s\n' "$expect" "$got" "$cmd"
  fi
}

# scratch repo checked out on a feature branch
SCRATCH=${TMPDIR:-/tmp}/block-main-push-test-repo
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
( cd "$SCRATCH" && git init -q . && git config user.email t@t && git config user.name t \
  && echo a > a && git add a && git commit -qm init && git checkout -q -b feat/x )

echo "== HEAD is main (cwd = $REPO) =="
run BLOCK "$REPO" 'git push'
run BLOCK "$REPO" 'git push origin'
run BLOCK "$REPO" 'git push origin main'
run BLOCK "$REPO" 'git push origin HEAD'
run BLOCK "$REPO" 'git push origin HEAD:main'
run BLOCK "$REPO" 'git push origin feat/x:main'
run BLOCK "$REPO" 'git push origin refs/heads/main'
run BLOCK "$REPO" 'git push origin +main'
run BLOCK "$REPO" 'git push --force origin main'
run BLOCK "$REPO" 'git push -f origin main'
run BLOCK "$REPO" 'git push origin :main'
run BLOCK "$REPO" 'git push origin --delete main'
run BLOCK "$REPO" 'git push origin -d main'
run BLOCK "$REPO" 'git push --all origin'
run BLOCK "$REPO" 'git push --mirror origin'
run BLOCK "$REPO" 'git push -u origin main'

echo "== HEAD is main, but the push does NOT target main =="
run ALLOW "$REPO" 'git push origin --delete feat/some-merged-branch'
run ALLOW "$REPO" 'git push origin -d feat/x'
run ALLOW "$REPO" 'git push origin feat/x'
run ALLOW "$REPO" 'git push -u origin feat/x'
run ALLOW "$REPO" 'git push origin main:feat/x'
run ALLOW "$REPO" 'git push origin :feat/x'
run ALLOW "$REPO" 'git push origin -o ci.skip feat/x'
run ALLOW "$REPO" 'git push --force-with-lease origin feat/x'
run ALLOW "$REPO" 'git push origin refs/heads/feat/x'

echo "== the word appears in a FILENAME, not as the subcommand =="
# Regression: matching "push" anywhere made the guard block reading its own
# source and its own test file whenever HEAD was main.
run ALLOW "$REPO" 'git show HEAD:.claude/hooks/block-main-push.sh'
run ALLOW "$REPO" 'git diff scripts/test-block-main-push.sh'
run ALLOW "$REPO" 'git log --oneline -- scripts/test-block-main-push.sh'
run ALLOW "$REPO" 'git add .claude/hooks/block-main-push.sh'
run ALLOW "$REPO" 'cat .claude/hooks/block-main-push.sh'
run ALLOW "$REPO" 'git log --grep=push --oneline'

echo "== git global options before the subcommand =="
run BLOCK "$REPO" 'git -C /tmp/repo push origin main'
run ALLOW "$REPO" 'git -C /tmp/repo push origin feat/x'
run BLOCK "$REPO" 'git -c user.name=x push origin main'

echo "== not a push at all =="
run ALLOW "$REPO" 'git status --short'
run ALLOW "$REPO" 'git log --oneline -5'
run ALLOW "$REPO" 'ls -la'
run ALLOW "$REPO" 'git pull --ff-only'

echo "== multi-command lines =="
run ALLOW "$REPO" 'git add -A && git commit -m wip && git push origin feat/x'
run BLOCK "$REPO" 'git push origin feat/x && git push origin main'
run BLOCK "$REPO" 'echo hi; git push origin main'

echo "== HEAD is a feature branch (cwd = scratch repo) =="
run ALLOW "$SCRATCH" 'git push'
run ALLOW "$SCRATCH" 'git push origin'
run ALLOW "$SCRATCH" 'git push origin HEAD'
run ALLOW "$SCRATCH" 'git push -u origin feat/x'
run BLOCK "$SCRATCH" 'git push origin main'
run BLOCK "$SCRATCH" 'git push origin HEAD:main'
run BLOCK "$SCRATCH" 'git push origin --delete main'

echo "== a broken PATH must not make the guard fail OPEN =="
# Regression: before the hook normalised PATH, a PATH without `grep` made every
# check silently succeed and every push was allowed, protected branch included.
EMPTYBIN=${TMPDIR:-/tmp}/block-main-push-empty-bin
rm -rf "$EMPTYBIN"; mkdir -p "$EMPTYBIN"
runp() {  # runp <expect> <PATH> <command>
  local expect="$1" path="$2" cmd="$3" rc got json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd")
  ( cd "$REPO" && printf '%s' "$json" | PATH="$path" "$HOOK" >/dev/null 2>&1 )
  rc=$?
  got=ALLOW; [ "$rc" -eq 2 ] && got=BLOCK
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1)); printf '  ok   %-5s (PATH stripped) %s\n' "$got" "$cmd"
  else
    fail=$((fail+1)); printf '  FAIL want=%s got=%s (PATH stripped) %s\n' "$expect" "$got" "$cmd"
  fi
}
runp BLOCK ""          'git push origin main'
runp BLOCK "$EMPTYBIN" 'git push origin main'
runp BLOCK "/nonexistent" 'git push'
runp ALLOW ""          'git push origin feat/x'
runp ALLOW "$EMPTYBIN" 'git push origin --delete feat/x'
rm -rf "$EMPTYBIN"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
