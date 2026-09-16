#!/bin/bash
# Hook 5: block commands that push TO the protected branch.
#
# PreToolUse(Bash). Reads the command from the hook JSON and decides from the
# push's DESTINATION, not from which branch happens to be checked out.
#
# History of over-blocking in this hook — each fix narrowed it, and every one of
# them was a guard that refused work it was never meant to refuse:
#   1. Blocked every Bash call whenever HEAD was main.
#   2. Blocked every push whenever HEAD was main. So deleting a merged feature
#      branch from main, or pushing any other branch, was refused even though
#      neither writes to main.
#   3. Matched the word "push" anywhere in the command, so `git show
#      HEAD:.../block-main-push.sh` and `git diff scripts/test-block-main-push.sh`
#      were blocked — the subcommand has to be the verb, not a substring of a
#      filename. All three verified against scripts/test-block-main-push.sh.
#
# The check that matters is the last line of defence, so it is written to fail
# CLOSED: see the PATH note below and the jq fallback.
#
# Exit codes: 0 = allow, 2 = block (stderr is shown to the user).
#
# Behaviour table: scripts/test-block-main-push.sh

set -u

# Guarantee the standard tools are reachable. A guard that cannot find `grep`
# or `jq` silently fails OPEN — verified: with a PATH missing grep, every push
# was allowed, including one straight at the protected branch. Prepending the
# system directories costs nothing and removes that whole failure mode.
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PATH

PROTECTED=main

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
else
  CMD=""
fi

# No parseable command (no jq, or a tool with no command field): fall back to the
# previous, coarser rule rather than waving the call through. Refusing to guess
# is the safe direction for a guard.
if [ -z "$CMD" ]; then
  if printf '%s' "$INPUT" | grep -Eq '\bgit\b[^;&|]*\bpush\b'; then
    BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ "$BR" = "$PROTECTED" ]; then
      echo "Blocked: could not parse the command, and HEAD is $PROTECTED." >&2
      echo "         Install jq so this hook can read the push target." >&2
      exit 2
    fi
  fi
  exit 0
fi

# Cheap prefilter. The real decision is the tokeniser below, which requires
# `push` to be the git SUBCOMMAND rather than a word that appears somewhere.
printf '%s' "$CMD" | grep -Eq '\bgit\b.*\bpush\b' || exit 0

CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

block() {
  echo "Blocked: this command writes to '$PROTECTED' ($1)." >&2
  echo "         Open a PR instead: gh pr create" >&2
  exit 2
}

# One command line can hold several commands; inspect each one separately.
SEGMENTS=$(printf '%s' "$CMD" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g')

while IFS= read -r seg; do
  case "$seg" in *git*) ;; *) continue ;; esac

  # shellcheck disable=SC2086
  set -- $seg
  saw_git=0
  seen_push=0
  args=""
  delete=0
  allrefs=0

  while [ "$#" -gt 0 ]; do
    tok="$1"; shift

    # 1. find the `git` verb
    if [ "$saw_git" -eq 0 ]; then
      [ "$tok" = git ] && saw_git=1
      continue
    fi

    # 2. the next non-option token must be `push`, or this is another subcommand
    if [ "$seen_push" -eq 0 ]; then
      case "$tok" in
        push) seen_push=1 ;;
        # git's own global options that take a SEPARATE value
        -C|-c|--git-dir|--work-tree|--exec-path|--namespace)
              [ "$#" -gt 0 ] && shift ;;
        -*)   : ;;
        *)    saw_git=0 ;;   # e.g. `git show …`, `git diff …` — not a push
      esac
      continue
    fi

    # 3. collect the push's own options and positionals
    case "$tok" in
      --delete|-d)    delete=1 ;;
      --all|--mirror) allrefs=1 ;;
      # options whose value is a SEPARATE token — consume it so it is never
      # mistaken for a refspec
      -o|--push-option|--receive-pack|--exec|--repo)
                      [ "$#" -gt 0 ] && shift ;;
      -*)             : ;;   # any other flag, including --force / -f / -u
      *)              args="$args $tok" ;;
    esac
  done

  [ "$seen_push" -eq 1 ] || continue
  [ "$allrefs" -eq 1 ] && block "--all / --mirror pushes every branch"

  # first positional is the remote; the rest are refspecs
  remote_seen=0
  refspecs=""
  for a in $args; do
    if [ "$remote_seen" -eq 0 ]; then remote_seen=1; continue; fi
    refspecs="$refspecs $a"
  done

  # No refspec pushes the CURRENT branch (push.default simple/current).
  if [ -z "$(printf '%s' "$refspecs" | tr -d '[:space:]')" ]; then
    [ "$CURRENT" = "$PROTECTED" ] && block "no refspec given, so it pushes the checked-out $PROTECTED"
    continue
  fi

  for rs in $refspecs; do
    rs=${rs#+}                          # force marker
    if [ "$delete" -eq 1 ]; then
      dst=$rs                           # --delete lists branch names, not refspecs
    else
      case "$rs" in
        *:*) dst=${rs#*:} ;;            # src:dst — destination is after the colon
        *)   dst=$rs ;;                 # bare name pushes to the same name
      esac
    fi
    dst=${dst#refs/heads/}
    [ "$dst" = HEAD ] && dst=$CURRENT   # HEAD resolves to the checked-out branch
    [ -z "$dst" ] && continue
    if [ "$dst" = "$PROTECTED" ]; then
      if [ "$delete" -eq 1 ]; then
        block "it deletes $PROTECTED"
      fi
      block "destination ref is $PROTECTED"
    fi
  done
done <<EOF
$SEGMENTS
EOF

exit 0
