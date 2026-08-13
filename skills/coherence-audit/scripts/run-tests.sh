#!/usr/bin/env bash
#
# run-tests.sh — the ONE command that runs the shared-script test suite
# =============================================================================
#
#   THE SINGLE DOCUMENTED COMMAND (from the repo root):
#
#       bash skills/coherence-audit/scripts/run-tests.sh
#
#   It can also be run from anywhere as `.../scripts/run-tests.sh` — it locates
#   its own directory and needs no arguments and no environment.
#
# WHAT IT COVERS
#   A. glob-overlap.sh vs tests/glob-overlap-vectors.tsv — schema §1 truth table
#      (all seven rows), plus the cases that table omits: normalization, `?`,
#      `*`-within-one-segment, zero-segment `**`, two-sided `**`, and set-vs-set.
#      Both the EXIT CODE and the exact TAB-separated evidence on stdout.
#   B. glob-overlap.sh error surface — every exit-2 path (arg count, missing
#      path, directory, malformed `**`), CRLF/whitespace tolerance, and the R6.6
#      "no dependency gating in the script" invariant.
#   C. entry-digest.sh — stability, the `state:` / `pre-approved-batch:`
#      EXCLUSION, detection of a changed declared-surface / accept-seed /
#      depends_on, order- and whitespace-insensitivity, and its exit-2 paths.
#
# EXIT
#   0 if every case passes; 1 if any case fails (so a caller can gate on it).
#
# harness-ops has no CI (spec Known Gap 2), so this is run by a human. That is
# exactly why it is one command with no setup.
#
set -eu

LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
GLOB_OVERLAP="$SCRIPT_DIR/glob-overlap.sh"
ENTRY_DIGEST="$SCRIPT_DIR/entry-digest.sh"
VECTORS="$SCRIPT_DIR/tests/glob-overlap-vectors.tsv"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/coherence-audit-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

PASSED=0
FAILED=0

ok() {
  PASSED=$((PASSED + 1))
  printf '  PASS  %s\n' "$1"
}
bad() {
  FAILED=$((FAILED + 1))
  printf '  FAIL  %s\n' "$1"
  shift
  while [ "$#" -gt 0 ]; do
    printf '          %s\n' "$1"
    shift
  done
}
section() {
  printf '\n%s\n' "$1"
  printf '%s\n' "-------------------------------------------------------------------"
}

# ===========================================================================
# preconditions
# ===========================================================================
section "Preconditions"
for f in "$GLOB_OVERLAP" "$ENTRY_DIGEST"; do
  base=$(basename "$f")
  if [ -f "$f" ] && [ -x "$f" ]; then
    ok "$base exists and is executable"
  else
    bad "$base exists and is executable" "not found or not executable: $f"
  fi
done
if [ -f "$VECTORS" ]; then
  ok "vector file exists ($(basename "$VECTORS"))"
else
  bad "vector file exists" "not found: $VECTORS"
fi

# ===========================================================================
# A. glob-overlap.sh — the vector table
# ===========================================================================
section "A. glob-overlap.sh — vectors (schema §1 truth table + the omitted cases)"

# write_surface <target-file> <";"-separated globs>
#   `(none)` produces an empty file; an empty element produces a blank line.
write_surface() {
  if [ "$2" = "(none)" ]; then
    : > "$1"
  else
    printf '%s\n' "$2" | tr ';' '\n' > "$1"
  fi
}

lineno=0
while IFS="$(printf '\t')" read -r expect surf_a surf_b evidence desc <&3; do
  lineno=$((lineno + 1))
  case "$expect" in
    '' | '#'*) continue ;;
  esac
  if [ -z "${desc:-}" ]; then
    bad "vector line $lineno" "malformed vector row (needs 5 TAB-separated fields): $expect"
    continue
  fi

  write_surface "$TMP/a.globs" "$surf_a"
  write_surface "$TMP/b.globs" "$surf_b"

  rc=0
  actual=$("$GLOB_OVERLAP" "$TMP/a.globs" "$TMP/b.globs" 2>"$TMP/stderr") || rc=$?

  label="[$expect] $surf_a  vs  $surf_b   ($desc)"

  if [ "$expect" = "no" ]; then
    if [ "$rc" -ne 0 ]; then
      bad "$label" "expected exit 0 (disjoint), got $rc" "stdout: [$actual]"
    elif [ -n "$actual" ]; then
      bad "$label" "expected EMPTY stdout on exit 0, got: [$actual]"
    else
      ok "$label"
    fi
    continue
  fi

  # expect = yes
  expected=$(printf '%s\n' "$evidence" | tr ';' '\n' | tr '>' "$(printf '\t')")
  if [ "$rc" -ne 1 ]; then
    bad "$label" "expected exit 1 (intersect), got $rc" "stdout: [$actual]" "stderr: [$(cat "$TMP/stderr")]"
  elif [ "$actual" != "$expected" ]; then
    bad "$label" "evidence mismatch" "expected: [$expected]" "actual:   [$actual]"
  else
    ok "$label"
  fi
done 3< "$VECTORS"

# ===========================================================================
# B. glob-overlap.sh — error surface, tolerance, and the R6.6 invariant
# ===========================================================================
section "B. glob-overlap.sh — exit-2 misuse, tolerance, R6.6"

printf 'src/auth/**\n' > "$TMP/ok_a.globs"
printf 'src/auth/login.py\n' > "$TMP/ok_b.globs"

# expect_two <label> <args...>
expect_two() {
  label="$1"
  shift
  rc=0
  out=$("$GLOB_OVERLAP" "$@" 2>"$TMP/stderr") || rc=$?
  if [ "$rc" -ne 2 ]; then
    bad "$label" "expected exit 2, got $rc" "stdout: [$out]"
  elif [ -n "$out" ]; then
    bad "$label" "exit 2 must leave stdout EMPTY, got: [$out]"
  elif [ ! -s "$TMP/stderr" ]; then
    bad "$label" "exit 2 must write a diagnostic to stderr, but stderr was empty"
  else
    ok "$label  (stderr: $(head -n 1 "$TMP/stderr"))"
  fi
}

expect_two "R6.4 zero arguments -> exit 2"
expect_two "R6.4 one argument -> exit 2" "$TMP/ok_a.globs"
expect_two "R6.6 three arguments -> exit 2 (no channel exists to pass dependency info)" \
  "$TMP/ok_a.globs" "$TMP/ok_b.globs" "extra"
expect_two "R6.4 nonexistent path (first arg) -> exit 2" "$TMP/does-not-exist" "$TMP/ok_b.globs"
expect_two "R6.4 nonexistent path (second arg) -> exit 2" "$TMP/ok_a.globs" "$TMP/does-not-exist"
mkdir -p "$TMP/adir"
expect_two "R6.4 directory instead of a file -> exit 2" "$TMP/adir" "$TMP/ok_b.globs"

printf 'a/x**y/b\n' > "$TMP/bad1.globs"
expect_two "malformed glob (** not a whole segment: a/x**y/b) -> exit 2" "$TMP/bad1.globs" "$TMP/ok_b.globs"
printf 'a/**b/c\n' > "$TMP/bad2.globs"
expect_two "malformed glob (** not a whole segment: a/**b/c) -> exit 2" "$TMP/ok_a.globs" "$TMP/bad2.globs"
printf '/\n' > "$TMP/bad3.globs"
expect_two "glob normalizing to an empty path -> exit 2" "$TMP/bad3.globs" "$TMP/ok_b.globs"

# CRLF + trailing whitespace tolerance (cannot be expressed in the TSV)
printf 'src/auth/**\r\n' > "$TMP/crlf.globs"
printf 'src/auth/login.py   \n' > "$TMP/trail.globs"
rc=0
out=$("$GLOB_OVERLAP" "$TMP/crlf.globs" "$TMP/trail.globs") || rc=$?
want=$(printf 'src/auth/**\tsrc/auth/login.py')
if [ "$rc" -eq 1 ] && [ "$out" = "$want" ]; then
  ok "CRLF + trailing-whitespace tolerance -> exit 1 with clean evidence"
else
  bad "CRLF + trailing-whitespace tolerance" "rc=$rc" "expected: [$want]" "actual:   [$out]"
fi

# R6.6 — no dependency gating anywhere in the executable body
if grep -v '^[[:space:]]*#' "$GLOB_OVERLAP" | grep -q 'depends_on'; then
  bad "R6.6 no depends_on logic in glob-overlap.sh" "found 'depends_on' outside comments"
else
  ok "R6.6 no depends_on logic in glob-overlap.sh (executable body is clean)"
fi

# The script must not touch the real filesystem: a glob that names a path which
# genuinely exists must be treated no differently from one that does not.
printf '%s\n' "$SCRIPT_DIR/**" > "$TMP/real_a.globs"
printf '%s\n' "$SCRIPT_DIR/definitely-not-on-disk/**" > "$TMP/real_b.globs"
rc=0
out=$("$GLOB_OVERLAP" "$TMP/real_a.globs" "$TMP/real_b.globs") || rc=$?
if [ "$rc" -eq 1 ]; then
  ok "no filesystem expansion — a nonexistent path still unifies under **"
else
  bad "no filesystem expansion" "expected exit 1, got $rc" "stdout: [$out]"
fi

# ===========================================================================
# C. entry-digest.sh — R10.3 / D20
# ===========================================================================
section "C. entry-digest.sh — shared normalization, machine-field exclusion"

MAN="$TMP/manifests"
mkdir -p "$MAN"

# write_manifest <outfile> <auth-globs ";"-sep> <auth-depends_on> <auth-accept-seed> <auth-state> <auth-preapproved>
write_manifest() {
  _out="$1"; _globs="$2"; _deps="$3"; _seed="$4"; _state="$5"; _pre="$6"
  {
    printf '# partition-manifest.md — login-stack\n'
    printf -- '- generated_at: 2026-08-07T00:00:00Z\n'
    printf -- '- goal: Build a login stack\n\n'
    printf '## Shared Decisions\n'
    printf '### SD1: Use SQLite for session storage\n'
    printf -- '- **Status**: resolved\n'
    printf -- '- **Rationale**: simplest thing that persists.\n\n'
    printf '## Features  (ordered — a dependency appears before its dependents)\n'
    printf '### session-core\n'
    printf -- '- declared-surface:\n'
    printf -- '  - src/session/**\n'
    printf -- '- depends_on: []\n'
    printf -- '- accept-seed: Sessions persist across requests and expire on logout.\n'
    printf -- '- pre-approved-batch: no\n'
    printf -- '- state: pending\n\n'
    printf '### auth\n'
    printf -- '- declared-surface:\n'
    printf '%s\n' "$_globs" | tr ';' '\n' | while IFS= read -r g; do
      [ -n "$g" ] && printf -- '  - %s\n' "$g"
    done
    printf -- '- depends_on: %s\n' "$_deps"
    printf -- '- accept-seed: %s\n' "$_seed"
    printf -- '- pre-approved-batch: %s\n' "$_pre"
    printf -- '- state: %s\n' "$_state"
  } > "$_out"
}

BASE_GLOBS='src/auth/**;app.py'
BASE_DEPS='[session-core]'
BASE_SEED='A user can log in and out with a persisted session.'

write_manifest "$MAN/base.md"        "$BASE_GLOBS"                  "$BASE_DEPS" "$BASE_SEED" "pending"   "no"
write_manifest "$MAN/machine.md"     "$BASE_GLOBS"                  "$BASE_DEPS" "$BASE_SEED" "generated" "yes"
write_manifest "$MAN/globorder.md"   'app.py;src/auth/**'           "$BASE_DEPS" "$BASE_SEED" "pending"   "no"
write_manifest "$MAN/surface.md"     "$BASE_GLOBS;src/widened/**"   "$BASE_DEPS" "$BASE_SEED" "pending"   "no"
write_manifest "$MAN/seed.md"        "$BASE_GLOBS"                  "$BASE_DEPS" "A user can log in." "pending" "no"
write_manifest "$MAN/deps.md"        "$BASE_GLOBS"                  "[]"         "$BASE_SEED" "pending"   "no"

# whitespace / CRLF / field-order variant of base.md — must hash identically
{
  printf '# partition-manifest.md — login-stack\r\n'
  printf -- '- generated_at: 2026-08-07T00:00:00Z\r\n'
  printf -- '- goal: Build a login stack\r\n\r\n'
  printf '## Shared Decisions\r\n'
  printf '### SD1: Use SQLite for session storage\r\n'
  printf -- '- **Status**: resolved\r\n\r\n'
  printf '## Features  (ordered — a dependency appears before its dependents)\r\n'
  printf '### session-core\r\n'
  printf -- '- declared-surface:\r\n'
  printf -- '  - src/session/**\r\n'
  printf -- '- depends_on: []\r\n'
  printf -- '- accept-seed: Sessions persist across requests and expire on logout.\r\n\r\n'
  printf '###    auth   \r\n'
  printf -- '- state: generated\r\n'
  printf -- '- accept-seed:   A user   can log in and    out with a persisted session.   \r\n'
  printf -- '- depends_on:   [ session-core ]\r\n'
  printf -- '- pre-approved-batch: yes\r\n'
  printf -- '- declared-surface:\r\n'
  printf -- '      - app.py  \r\n'
  printf -- '      - src/auth/**\r\n'
} > "$MAN/cosmetic.md"

# a legacy manifest: no `state:` and no `pre-approved-batch:` at all
{
  printf '## Features\n'
  printf '### auth\n'
  printf -- '- declared-surface:\n'
  printf -- '  - src/auth/**\n'
  printf -- '  - app.py\n'
  printf -- '- depends_on: [session-core]\n'
  printf -- '- accept-seed: %s\n' "$BASE_SEED"
} > "$MAN/legacy.md"

digest_of() { "$ENTRY_DIGEST" "$1" "$2"; }

D_BASE=$(digest_of "$MAN/base.md" auth)

# 1. stable across two invocations
D_BASE2=$(digest_of "$MAN/base.md" auth)
if [ "$D_BASE" = "$D_BASE2" ]; then
  ok "stable across two invocations on the same input"
else
  bad "stable across two invocations" "$D_BASE" "$D_BASE2"
fi

# 2. shape: 64 lowercase hex chars, nothing else
if printf '%s' "$D_BASE" | grep -q '^[0-9a-f]\{64\}$'; then
  ok "stdout is a bare lowercase 64-char sha256 hex digest"
else
  bad "stdout is a bare lowercase sha256 hex digest" "got: [$D_BASE]"
fi

# same_digest <label> <manifest> <feature>
same_digest() {
  d=$(digest_of "$2" "$3")
  if [ "$d" = "$D_BASE" ]; then
    ok "$1"
  else
    bad "$1" "expected $D_BASE" "actual   $d"
  fi
}
diff_digest() {
  d=$(digest_of "$2" "$3")
  if [ "$d" != "$D_BASE" ]; then
    ok "$1"
  else
    bad "$1" "digest did not change: $d"
  fi
}

# 3. THE point of D20 — machine-flipped fields are excluded
same_digest "D20 EXCLUSION — flipping state: and pre-approved-batch: leaves the digest UNCHANGED" \
  "$MAN/machine.md" auth
same_digest "a legacy entry with no state:/pre-approved-batch: lines hashes identically" \
  "$MAN/legacy.md" auth

# 4. normalization is insensitive to cosmetics
same_digest "R10.3 — glob-list order does not affect the digest (sorted)" \
  "$MAN/globorder.md" auth
same_digest "R10.3 — CRLF, indentation, field order, and collapsed whitespace do not affect the digest" \
  "$MAN/cosmetic.md" auth

# 5. human-owned edits ARE detected
diff_digest "R5.3 — a widened declared-surface changes the digest" "$MAN/surface.md" auth
diff_digest "R5.3 — a changed accept-seed changes the digest" "$MAN/seed.md" auth
diff_digest "a changed depends_on changes the digest" "$MAN/deps.md" auth

# 6. per-feature scoping
if [ "$(digest_of "$MAN/base.md" session-core)" != "$D_BASE" ]; then
  ok "a different feature in the same manifest yields a different digest"
else
  bad "per-feature scoping" "session-core hashed to the same value as auth"
fi

# 7. the canonical text is inspectable and excludes the machine fields
canon=$("$ENTRY_DIGEST" --canonical "$MAN/machine.md" auth)
if printf '%s' "$canon" | grep -q 'state:\|pre-approved-batch:'; then
  bad "--canonical text excludes machine-owned fields" "canonical text: [$canon]"
elif [ "$canon" = "$("$ENTRY_DIGEST" --canonical "$MAN/base.md" auth)" ]; then
  ok "--canonical text is byte-identical across a machine-field flip"
else
  bad "--canonical text is byte-identical across a machine-field flip" "[$canon]"
fi

# 8. exit-2 surface
digest_expect_two() {
  label="$1"
  shift
  rc=0
  out=$("$ENTRY_DIGEST" "$@" 2>"$TMP/stderr") || rc=$?
  if [ "$rc" -ne 2 ]; then
    bad "$label" "expected exit 2, got $rc" "stdout: [$out]"
  elif [ -n "$out" ]; then
    bad "$label" "exit 2 must leave stdout EMPTY, got: [$out]"
  elif [ ! -s "$TMP/stderr" ]; then
    bad "$label" "exit 2 must write a diagnostic to stderr, but stderr was empty"
  else
    ok "$label  (stderr: $(head -n 1 "$TMP/stderr"))"
  fi
}

digest_expect_two "entry-digest: one argument -> exit 2" "$MAN/base.md"
digest_expect_two "entry-digest: zero arguments -> exit 2"
digest_expect_two "entry-digest: three arguments -> exit 2" "$MAN/base.md" auth extra
digest_expect_two "entry-digest: nonexistent manifest -> exit 2" "$MAN/nope.md" auth
digest_expect_two "entry-digest: directory instead of a manifest -> exit 2" "$MAN" auth
digest_expect_two "entry-digest: unknown feature-id -> exit 2" "$MAN/base.md" no-such-feature
digest_expect_two "entry-digest: an SD heading is not a feature -> exit 2" "$MAN/base.md" "SD1: Use SQLite for session storage"

# ===========================================================================
# D. portability contract — the full-corpus sweep and root-resolution parity
# ===========================================================================
#
# The PreToolUse hook only inspects the NEXT write, so a skill can be listed as
# converted and still drift on disk. This sweep is the whole-corpus check, and
# it is runtime-independent (plain bash), which also covers a contributor
# working in agy who never triggers a Claude Code hook.

section "D. portability contract"

REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
LINT="$REPO_ROOT/scripts/portability-lint.sh"
MAP="$REPO_ROOT/references/runtime-tools.md"
CONVERTED="$REPO_ROOT/references/converted-skills.md"

for f in "$LINT" "$MAP" "$CONVERTED"; do
  base=$(basename "$f")
  if [ -f "$f" ]; then
    ok "$base exists"
  else
    bad "$base exists" "not found: $f"
  fi
done

if [ -f "$LINT" ] && [ -x "$LINT" ]; then
  if "$LINT" --sweep >"$TMP/sweep.out" 2>"$TMP/sweep.err"; then
    ok "portability sweep is clean across every listed skill"
  else
    bad "portability sweep is clean across every listed skill" \
        "$(head -n 6 "$TMP/sweep.err" | tr '\n' ' ')"
  fi
else
  bad "portability-lint.sh is executable" "not executable: $LINT"
fi

# --- root-resolution parity -------------------------------------------------
# `resolve-harness-root` claims two runtimes reach the SAME repo root by
# different means: ${CLAUDE_PLUGIN_ROOT} on Claude Code, a two-level ascent from
# the skill directory on agy. The plugins/harness-ops -> ../ symlink means the
# two can be different STRINGS for the same files, so compare resolved identity
# and script OUTPUT — never the path text.

ascent_root=$(cd "$REPO_ROOT/skills/coherence-audit/../.." && pwd -P)
direct_root=$(cd "$REPO_ROOT" && pwd -P)
if [ "$ascent_root" = "$direct_root" ]; then
  ok "resolve-harness-root: two-level ascent resolves to the repo root"
else
  bad "resolve-harness-root: two-level ascent resolves to the repo root" \
      "ascent: $ascent_root" "direct: $direct_root"
fi

if [ -d "$ascent_root/skills" ] && [ -d "$ascent_root/agents" ]; then
  ok "resolve-harness-root: validation probes (skills/, agents/) both present"
else
  bad "resolve-harness-root: validation probes (skills/, agents/) both present" \
      "missing under $ascent_root"
fi

# The symlinked path is a different string for the same files; the contract says
# compare output, so prove the pinned script agrees through both spellings.
sym_root="$REPO_ROOT/plugins/harness-ops"
if [ -d "$sym_root" ]; then
  write_surface "$TMP/parity-a" 'src/api/**/*.ts'
  write_surface "$TMP/parity-b" 'src/api/handlers/*.ts'
  set +e
  out_direct=$("$ascent_root/skills/coherence-audit/scripts/glob-overlap.sh" "$TMP/parity-a" "$TMP/parity-b" 2>&1); rc_direct=$?
  out_sym=$("$sym_root/skills/coherence-audit/scripts/glob-overlap.sh" "$TMP/parity-a" "$TMP/parity-b" 2>&1); rc_sym=$?
  set -e
  # NOTE: this is same-runtime, two-spelling parity — it proves the symlink does
  # not change the result. It is NOT cross-runtime evidence; that requires an
  # actual agy run (scripts/pilot-verify.sh).
  if [ "$out_direct" = "$out_sym" ] && [ "$rc_direct" -eq "$rc_sym" ]; then
    ok "pinned-script: same output through both root spellings, same runtime (exit $rc_direct)"
  else
    bad "pinned-script: same output through both root spellings, same runtime" \
        "direct(exit $rc_direct): $out_direct" "symlink(exit $rc_sym): $out_sym"
  fi
else
  bad "pinned-script parity: plugins/harness-ops symlink present" "not found: $sym_root"
fi

# --- hook path-guard regression ---------------------------------------------
# The PreToolUse guard compares the target against REPO_ROOT. With logical `pwd`
# the symlinked plugin root made REPO_ROOT `<repo>/plugins/harness-ops`, so the
# guard rejected every real file and the gate silently no-opped. Both spellings
# must block, and a foreign path must not.
# The probes send a PENDING WRITE payload against a file that is CLEAN on disk.
# An earlier version of these cases planted the violation on disk first, which
# only proved the hook catches an already-dirty file — PostToolUse semantics one
# write late, and exactly the shape D5 rejected. Never plant on disk here.
guard_probe() {   # guard_probe <lint-script> <target-path> <pending-content>
  jq -nc --arg p "$2" --arg c "$3" \
    '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' \
    | bash "$1" --hook >/dev/null 2>&1
  echo $?
}
if [ -f "$LINT" ] && [ -n "${CONVERTED:-}" ] && grep -q '^| coherence-audit' "$CONVERTED"; then
  clean_target="$REPO_ROOT/skills/coherence-audit/SKILL.md"
  dirty='Read `../../references/runtime-tools.md` first.
Use the Read tool to load the spec.
Compute via `capability:run-glob-overlap` and `capability:resolve-harness-root`
and `capability:read-declared-surface-schema` and `capability:spawn-inline-checker`.'
  legit='Read `../../references/runtime-tools.md` first.
A missing `Agent` tool marks the tier unverified; count `Agent.subagent_type`.
Compute via `capability:run-glob-overlap` and `capability:resolve-harness-root`
and `capability:read-declared-surface-schema` and `capability:spawn-inline-checker`.'

  sum_before=$(shasum "$clean_target" | awk '{print $1}')
  rc_a=$(guard_probe "$LINT" "$clean_target" "$dirty")
  rc_b=$(guard_probe "$REPO_ROOT/plugins/harness-ops/scripts/portability-lint.sh" "$clean_target" "$dirty")
  rc_c=$(guard_probe "$LINT" "/tmp/definitely-not-this-repo/SKILL.md" "$dirty")
  rc_d=$(guard_probe "$LINT" "$clean_target" "$legit")
  rc_e=$(guard_probe "$LINT" "$REPO_ROOT/skills/loop/SKILL.md" "$dirty")

  [ "$rc_a" = "2" ] && ok "hook DENIES a pending violating write (R6.1)" \
                    || bad "hook DENIES a pending violating write (R6.1)" "exit $rc_a, expected 2 — hook may be linting disk instead of the payload"
  [ "$rc_b" = "2" ] && ok "hook denies via the plugins/ symlink root too" \
                    || bad "hook denies via the plugins/ symlink root too" "exit $rc_b, expected 2 (logical-pwd regression)"
  [ "$rc_c" = "0" ] && ok "hook no-ops on a path outside this repo" \
                    || bad "hook no-ops on a path outside this repo" "exit $rc_c, expected 0"
  [ "$rc_d" = "0" ] && ok "hook allows a pending write with only bare mentions" \
                    || bad "hook allows a pending write with only bare mentions" "exit $rc_d, expected 0 — false positive"
  [ "$rc_e" = "0" ] && ok "hook no-ops on an unconverted skill" \
                    || bad "hook no-ops on an unconverted skill" "exit $rc_e, expected 0"

  # MultiEdit carries `edits[]` (no top-level new_string) and Edit may carry
  # replace_all. Both previously fell through to disk-linting / a single-
  # occurrence patch, so a violating write sailed past the gate.
  me_probe() {   # me_probe <target> <old> <new> [replace_all]
    jq -nc --arg p "$1" --arg o "$2" --arg n "$3" \
      '{tool_name:"MultiEdit",tool_input:{file_path:$p,edits:[{old_string:$o,new_string:$n}]}}' \
      | bash "$LINT" --hook >/dev/null 2>&1; echo $?
  }
  ra_probe() {
    jq -nc --arg p "$1" --arg o "$2" --arg n "$3" \
      '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n,replace_all:true}}' \
      | bash "$LINT" --hook >/dev/null 2>&1; echo $?
  }
  anchor='## Overlap tier'
  grep -q "$anchor" "$clean_target" || anchor=$(grep -m1 '^## ' "$clean_target")

  rc_f=$(me_probe "$clean_target" "$anchor" "$anchor
Use the Read tool to load the spec.")
  rc_g=$(me_probe "$clean_target" "$anchor" "$anchor
A missing \`Agent\` tool marks the tier unverified.")
  rc_h=$(ra_probe "$clean_target" '---' '---
Use the Grep tool to scan.')

  [ "$rc_f" = "2" ] && ok "hook denies a violating MultiEdit (edits[] branch)" \
                    || bad "hook denies a violating MultiEdit (edits[] branch)" "exit $rc_f, expected 2 — edits[] may be falling through to disk"
  [ "$rc_g" = "0" ] && ok "hook allows a MultiEdit with only bare mentions" \
                    || bad "hook allows a MultiEdit with only bare mentions" "exit $rc_g, expected 0 — false positive"
  [ "$rc_h" = "2" ] && ok "hook denies a violating replace_all edit" \
                    || bad "hook denies a violating replace_all edit" "exit $rc_h, expected 2 — replace_all may be patching only the first match"

  sum_after=$(shasum "$clean_target" | awk '{print $1}')
  if [ "$sum_before" = "$sum_after" ]; then
    ok "guard probes left the target byte-identical on disk"
  else
    bad "guard probes left the target byte-identical on disk" \
        "before: $sum_before" "after:  $sum_after"
  fi
fi

# ===========================================================================
# summary
# ===========================================================================
printf '\n===================================================================\n'
printf '  passed: %s   failed: %s\n' "$PASSED" "$FAILED"
printf '===================================================================\n'

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
