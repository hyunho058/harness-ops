#!/usr/bin/env bash
# TT3 — acceptance tests for spec check-harness-refresh R3 (session_files.py).
# Black box: drives only the CLI, with HOME pointed at a fixture directory.
# Expected values come from the spec (R3, D7, D8, D2), never from the implementation.
set -u

cd "$(dirname "$0")/../../.." || exit 1
SCRIPT="skills/check-harness/scripts/session_files.py"

T0="$(mktemp -d)"
trap 'rm -rf "$T0"' EXIT
# Resolve the scratch root once so fixture spellings match what D2 says is printed.
T="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$T0")"

FAILS=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1${2:+: $2}"; FAILS=$((FAILS + 1)); }

# D7 encoding: resolved absolute path, every char outside [A-Za-z0-9] -> '-'.
enc() {
  python3 -c 'import os,re,sys;print(re.sub(r"[^A-Za-z0-9]","-",os.path.realpath(sys.argv[1])))' "$1"
}
resolve() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }
# set_age FILE DAYS — mtime DAYS days ago
set_age() {
  python3 -c 'import os,sys,time;t=time.time()-float(sys.argv[2])*86400;os.utime(sys.argv[1],(t,t))' "$1" "$2"
}
mk_session() { mkdir -p "$(dirname "$1")"; printf '{"type":"user"}\n' > "$1"; }
git_init_commit() {
  git init -q "$1" &&
  git -C "$1" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
}
run() { # run HOME_DIR OUT ERR args... ; sets RC
  local h="$1" o="$2" e="$3"; shift 3
  HOME="$h" GIT_CEILING_DIRECTORIES="$T" python3 "$SCRIPT" "$@" >"$o" 2>"$e"
  RC=$?
}

# ---------------------------------------------------------------- R3.1
c="r3_1_subagent_transcripts_never_count"
H="$T/r31/home"; P="$H/.claude/projects/-p"
mk_session "$P/s1.jsonl"
mk_session "$P/s1/subagents/agent-x.jsonl"
run "$H" "$T/r31.out" "$T/r31.err" --scope overall
exp="$(resolve "$P/s1.jsonl")"
if [ "$RC" -eq 0 ] && [ "$(cat "$T/r31.out")" = "$exp" ]; then ok "$c"
else fail "$c" "rc=$RC stdout=$(tr '\n' '|' < "$T/r31.out")"; fi

# ---------------------------------------------------------------- R3.2
c="r3_2_project_scope_exact_dir_plus_worktrees"
W="$T/r32"; H="$W/home"; mkdir -p "$W"
git_init_commit "$W/proj" >/dev/null 2>&1
git -C "$W/proj" worktree add -q "$W/proj-wt" >/dev/null 2>&1
mkdir -p "$W/proj-old"
[ -d "$W/proj-wt" ] || fail "$c-fixture" "git worktree add failed"
E_PROJ="$(enc "$W/proj")"; E_WT="$(enc "$W/proj-wt")"; E_OLD="$(enc "$W/proj-old")"
PR="$H/.claude/projects"
mk_session "$PR/$E_PROJ/a.jsonl"
mk_session "$PR/$E_WT/b.jsonl"
mk_session "$PR/$E_OLD/c.jsonl"
run "$H" "$T/r32.out" "$T/r32.err" --scope project --project-dir "$W/proj"
exp="$(printf '%s\n' "$(resolve "$PR/$E_PROJ/a.jsonl")" "$(resolve "$PR/$E_WT/b.jsonl")" | LC_ALL=C sort)"
if [ "$RC" -eq 0 ] && [ "$(cat "$T/r32.out")" = "$exp" ]; then ok "$c-stdout"
else fail "$c-stdout" "rc=$RC stdout=$(tr '\n' '|' < "$T/r32.out")"; fi
if grep -E '^warning: excluded prefix-matching session dir' "$T/r32.err" | grep -qF -- "$E_OLD"; then
  ok "$c-warning"
else fail "$c-warning" "stderr=$(tr '\n' '|' < "$T/r32.err")"; fi

# ---------------------------------------------------------------- R3.3
c="r3_3_window_defaults_to_30_days"
H="$T/r33/home"; P="$H/.claude/projects/-w"
for d in 5 25 40; do mk_session "$P/d$d.jsonl"; set_age "$P/d$d.jsonl" "$d"; done
D5="$(resolve "$P/d5.jsonl")"; D25="$(resolve "$P/d25.jsonl")"
run "$H" "$T/r33a.out" "$T/r33a.err" --scope overall
exp="$(printf '%s\n' "$D5" "$D25" | LC_ALL=C sort)"
if [ "$RC" -eq 0 ] && [ "$(cat "$T/r33a.out")" = "$exp" ]; then ok "$c-default"
else fail "$c-default" "rc=$RC stdout=$(tr '\n' '|' < "$T/r33a.out")"; fi
run "$H" "$T/r33b.out" "$T/r33b.err" --scope overall --days 7
if [ "$RC" -eq 0 ] && [ "$(cat "$T/r33b.out")" = "$D5" ]; then ok "$c-days7"
else fail "$c-days7" "rc=$RC stdout=$(tr '\n' '|' < "$T/r33b.out")"; fi

# ---------------------------------------------------------------- R3.4
c="r3_4_paths_resolved_before_encoding"
W="$T/r34"; H="$W/home"; mkdir -p "$W/proj"
ln -s "$W/proj" "$W/link"
E_PROJ="$(enc "$W/proj")"
mk_session "$H/.claude/projects/$E_PROJ/s.jsonl"
run "$H" "$T/r34.out" "$T/r34.err" --scope project --project-dir "$W/link"
exp="$(resolve "$H/.claude/projects/$E_PROJ/s.jsonl")"
if [ "$RC" -eq 0 ] && grep -qxF -- "$exp" "$T/r34.out"; then ok "$c"
else fail "$c" "rc=$RC stdout=$(tr '\n' '|' < "$T/r34.out")"; fi

# ---------------------------------------------------------------- R3.5
c="r3_5_project_scope_requires_project_dir"
H="$T/r35/home"; mk_session "$H/.claude/projects/-q/s.jsonl"
run "$H" "$T/r35.out" "$T/r35.err" --scope project
# python3 itself exits 2 for a missing script file, so require the script to exist.
if [ ! -f "$SCRIPT" ]; then fail "$c" "$SCRIPT does not exist"
elif [ "$RC" -eq 2 ]; then ok "$c"; else fail "$c" "rc=$RC (want 2)"; fi

# ---------------------------------------------------------------- R3.6
c="r3_6_non_git_dir_falls_back_to_exact_dir"
W="$T/r36"; H="$W/home"; mkdir -p "$W/plain"
E_PLAIN="$(enc "$W/plain")"
mk_session "$H/.claude/projects/$E_PLAIN/s.jsonl"
run "$H" "$T/r36.out" "$T/r36.err" --scope project --project-dir "$W/plain"
exp="$(resolve "$H/.claude/projects/$E_PLAIN/s.jsonl")"
if [ "$RC" -eq 0 ]; then ok "$c-exit0"; else fail "$c-exit0" "rc=$RC"; fi
if [ "$(cat "$T/r36.out")" = "$exp" ]; then ok "$c-stdout"
else fail "$c-stdout" "stdout=$(tr '\n' '|' < "$T/r36.out")"; fi
if grep -qE '^warning: git unavailable' "$T/r36.err"; then ok "$c-warning"
else fail "$c-warning" "stderr=$(tr '\n' '|' < "$T/r36.err")"; fi

# ---------------------------------------------------------------- R3.7
c="r3_7_with_params_echoes_effective_arguments"
W="$T/r37"; H="$W/home"; mkdir -p "$W"
git_init_commit "$W/proj" >/dev/null 2>&1
E_PROJ="$(enc "$W/proj")"; PD="$H/.claude/projects/$E_PROJ"
mk_session "$PD/new.jsonl"
mk_session "$PD/old.jsonl"; set_age "$PD/old.jsonl" 10
run "$H" "$T/r37.out" "$T/r37.err" --scope project --project-dir "$W/proj" --days 7 --with-params
RP="$(resolve "$W/proj")"
first="$(head -n 1 "$T/r37.out")"
case "$first" in
  "# params "*)
    if printf '%s' "${first#\# params }" |
       jq -e --arg pd "$RP" '.scope == "project" and .project_dir == $pd and .days == 7' >/dev/null 2>&1
    then ok "$c-params"; else fail "$c-params" "first line: $first"; fi ;;
  *) fail "$c-params" "rc=$RC first line: $first" ;;
esac
rest="$(tail -n +2 "$T/r37.out")"
if [ "$RC" -eq 0 ] && [ "$rest" = "$(resolve "$PD/new.jsonl")" ]; then ok "$c-paths"
else fail "$c-paths" "rc=$RC rest=$(printf '%s' "$rest" | tr '\n' '|')"; fi

echo "tt3_session_files: $FAILS failure(s)"
[ "$FAILS" -eq 0 ]
