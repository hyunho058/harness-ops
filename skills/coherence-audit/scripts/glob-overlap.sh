#!/usr/bin/env bash
#
# glob-overlap.sh — deterministic glob-SET intersection (the overlap contract)
# =============================================================================
#
# PURPOSE
#   ONE shared implementation of the glob set-intersection defined by
#   `skills/coherence-audit/references/declared-surface-schema.md` §1
#   ("Glob semantics — deterministic, set-intersectable").
#
#   Both callers run THIS script, never their own reasoning:
#     - `decompose`      — its step-3 partition pre-flight (one call per feature pair)
#     - `coherence-audit`— its tier-2 overlap check (one call per spec pair)
#   Because both sides execute the same bytes, they cannot disagree about the
#   same pair. That is the whole point of extracting it.
#
# USAGE
#   glob-overlap.sh <surface-a-file> <surface-b-file>
#
#   Each argument is a path to a file holding ONE GLOB PER LINE — i.e. one
#   *surface* (glob SET) per file, which matches the contract's unit (§1 defines
#   overlap between glob SETS, not single globs). Globs are NEVER passed through
#   argv, so the shell can never expand one against the real filesystem.
#
#   Blank lines and lines whose first non-blank character is `#` are ignored,
#   so a caller may pass a commented vector file directly.
#
# EXIT CODES  (the result space 0/1 is deliberately DISJOINT from the error
#              space 2 — this is a RELATION question where both answers are
#              legitimate results, unlike a validity question where any
#              non-zero means "bad")
#   0  surfaces are DISJOINT.   stdout is EMPTY.
#   1  surfaces INTERSECT.      stdout carries one TAB-separated
#                               `<globA><TAB><globB>` line per intersecting
#                               pair — the evidence both callers must report.
#                               Order is A-major, then B; deterministic.
#   2  usage or input error (wrong arg count, missing/unreadable path,
#      malformed glob). Diagnostics on stderr; stdout stays EMPTY.
#
# NORMALIZATION  (schema §1 "Normalization"; applied to every line before any
#                 comparison)
#   1. Tolerate CRLF: a trailing `\r` is stripped.
#   2. Leading and trailing whitespace is stripped.
#   3. Blank lines and `#` comment lines are dropped.
#   4. The line is split on `/` into segments; then
#        - empty segments are dropped  → this strips a leading `/`,
#          collapses `//` runs to `/`, and drops a trailing `/`;
#        - segments equal to `.` are dropped → this strips `./`, both leading
#          and interior.
#      Segment-wise dropping is used (rather than textual `s|\./||g`) so a
#      `..` segment is never mangled into `.`.
#   5. Segments are rejoined with a single `/`.
#   6. Duplicate globs within ONE surface are collapsed to the first
#      occurrence, so evidence never repeats a pair.
#
# WILDCARDS  (schema §1 "Wildcards")
#   *   any run of characters WITHIN ONE SEGMENT (never crosses `/`; may match
#       zero characters).
#   ?   exactly one character within one segment.
#   **  ZERO OR MORE WHOLE SEGMENTS (crosses `/`). Valid ONLY as a complete
#       segment: `a/**`, `a/**/b`, `**/b`, `**`. A `**` that is not a whole
#       segment (e.g. `a/x**y/b`) is MALFORMED INPUT → exit 2.
#
# OVERLAP
#   Two globs OVERLAP iff at least one concrete repo path is matched by BOTH.
#   This is a glob-vs-glob INTERSECTION-NONEMPTINESS test computed by
#   segment-wise unification with backtracking (literal≡literal; `*`/`?` unify
#   one segment against the other side's segment pattern; `**` unifies
#   zero-or-more segments on the other side). BOTH sides may contain `**`, so
#   the unification is genuinely two-sided — `src/**/util.py` vs
#   `src/**/auth/util.py` is handled.
#
#   It is NOT filesystem expansion: nothing is globbed against the real disk and
#   no file is required to exist.
#
#   Two SURFACES overlap iff ANY glob in A overlaps ANY glob in B.
#
# WHAT THIS SCRIPT DOES NOT DO  (R6.6 / the D7 boundary — do not add it here)
#   NO dependency gating. It contains no `depends_on` logic of any kind. WHICH
#   pairs a non-empty intersection is applied to stays in each caller, because
#   the callers legitimately differ (decompose gates against the manifest's
#   `depends_on`, coherence-audit against the specs').
#
# PORTABILITY
#   bash + POSIX awk only. No GNU-isms: no `sed -r`, no `grep -P`, no
#   `readlink -f`, no `mapfile`, no bash-4 features. Verified on macOS/Darwin
#   (bash 3.2 + BSD one-true-awk).
#
# TESTS
#   bash skills/coherence-audit/scripts/run-tests.sh
#
set -eu

PROG="glob-overlap.sh"

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }

# --- argument validation ---------------------------------------------------
if [ "$#" -ne 2 ]; then
  err "usage: $PROG <surface-a-file> <surface-b-file>"
  err "each file holds ONE GLOB PER LINE (one surface per file)"
  exit 2
fi

for _p in "$1" "$2"; do
  if [ ! -e "$_p" ]; then
    err "no such file: $_p"
    exit 2
  fi
  if [ -d "$_p" ]; then
    err "is a directory, expected a file of globs: $_p"
    exit 2
  fi
  if [ ! -r "$_p" ]; then
    err "file not readable: $_p"
    exit 2
  fi
done

# --- the computation -------------------------------------------------------
# awk exits 0 (disjoint) / 1 (intersect) / 2 (malformed glob); the wrapper
# passes that status straight through.
status=0
awk '
# ---------------------------------------------------------------------------
# fail() — diagnostic to stderr, stdout untouched, exit 2.
# "cat 1>&2" is used instead of "/dev/stderr" because the latter is a
# gawk/BSD extension rather than POSIX awk.
# ---------------------------------------------------------------------------
function fail(msg) {
  print PROG ": " msg | STDERR
  close(STDERR)
  exit 2
}

# ---------------------------------------------------------------------------
# load() — read one surface file, normalize each line, validate, dedupe.
# Fills arr[1..n]; returns n.
# ---------------------------------------------------------------------------
function load(path, arr,   line, r, i, nseg, seg, out, s, k, n, seen) {
  n = 0
  while ((r = (getline line < path)) > 0) {
    sub(/^[ \t]+/, "", line)
    sub(/[ \t\r]+$/, "", line)
    if (line == "") continue
    if (substr(line, 1, 1) == "#") continue
    if (index(line, "\t") > 0)
      fail("glob contains a TAB, which would corrupt the TAB-separated evidence: [" line "] in " path)
    nseg = split(line, seg, "/")
    out = ""
    k = 0
    for (i = 1; i <= nseg; i++) {
      s = seg[i]
      if (s == "" || s == ".") continue
      if (index(s, "**") > 0 && s != "**")
        fail("invalid glob: \"**\" must be a whole path segment: [" line "] in " path)
      k++
      if (k == 1) out = s; else out = out "/" s
    }
    if (k == 0)
      fail("glob normalizes to an empty path: [" line "] in " path)
    if (out in seen) continue
    seen[out] = 1
    n++
    arr[n] = out
  }
  close(path)
  if (r < 0) fail("cannot read: " path)
  return n
}

# ---------------------------------------------------------------------------
# segX() / segRec() — SEGMENT-level intersection nonemptiness.
#
# Two single-segment patterns (literals, `*` = zero-or-more chars, `?` = exactly
# one char) intersect iff some concrete segment string matches BOTH. Computed as
# reachability in the product of the two patterns read as NFAs:
#   - `*` has an epsilon edge (matches zero chars) AND a self-loop (consumes any
#     char and stays);
#   - `?` consumes any one char and advances;
#   - a literal consumes exactly itself and advances.
# Accepting when BOTH patterns are exhausted.
#
# Every recursive call strictly increases p+q (the `*`-vs-`*` consume step, the
# only one that would not, is skipped because the two epsilon branches above it
# already cover it), so the recursion terminates; SMEMO makes it polynomial.
# SID namespaces the memo per pattern pair, so no array delete is needed.
# ---------------------------------------------------------------------------
function segX(a, b) {
  SID++
  return segRec(a, b, 1, 1)
}
function segRec(a, b, p, q,   key, la, lb, ca, cb, na, nb, aAny, bAny) {
  key = SID SUBSEP p SUBSEP q
  if (key in SMEMO) return SMEMO[key]
  SMEMO[key] = 0
  la = length(a)
  lb = length(b)
  # epsilon: a `*` on either side may match zero characters
  if (p <= la && substr(a, p, 1) == "*") {
    if (segRec(a, b, p + 1, q)) { SMEMO[key] = 1; return 1 }
  }
  if (q <= lb && substr(b, q, 1) == "*") {
    if (segRec(a, b, p, q + 1)) { SMEMO[key] = 1; return 1 }
  }
  if (p > la && q > lb) { SMEMO[key] = 1; return 1 }
  if (p > la || q > lb) return 0
  ca = substr(a, p, 1)
  cb = substr(b, q, 1)
  # `*` vs `*`: consuming a character returns to (p,q); the epsilon branches
  # above already decided this state, so there is nothing left to try.
  if (ca == "*" && cb == "*") return 0
  aAny = (ca == "*" || ca == "?")
  bAny = (cb == "*" || cb == "?")
  if (!aAny && !bAny && ca != cb) return 0
  na = (ca == "*") ? p : p + 1
  nb = (cb == "*") ? q : q + 1
  if (segRec(a, b, na, nb)) { SMEMO[key] = 1; return 1 }
  return 0
}

# ---------------------------------------------------------------------------
# pathX() / pathRec() — PATH-level intersection nonemptiness (two-sided `**`).
#
# PA[] / PB[] hold the normalized segment lists. At state (i,j):
#   - both exhausted                → intersect;
#   - one exhausted                 → intersect iff every remaining segment on
#                                     the other side is `**` (each matches zero
#                                     segments);
#   - `**` on EITHER side           → branch: it absorbs zero segments (advance
#                                     that side), or it absorbs the head segment
#                                     of the other side (advance the other side).
#                                     Every non-`**` segment pattern is
#                                     satisfiable by at least one concrete
#                                     segment, so absorption is always legal.
#   - two plain segment patterns    → they must intersect at the segment level,
#                                     then advance both.
# Both branches strictly increase i+j, so the backtracking terminates; PMEMO
# makes it a DP over segment pairs. PID namespaces the memo per glob pair.
# ---------------------------------------------------------------------------
function pathX(a, b,   m, n) {
  PID++
  m = split(a, PA, "/")
  n = split(b, PB, "/")
  return pathRec(1, 1, m, n)
}
function pathRec(i, j, m, n,   key, k) {
  key = PID SUBSEP i SUBSEP j
  if (key in PMEMO) return PMEMO[key]
  PMEMO[key] = 0
  if (i > m && j > n) { PMEMO[key] = 1; return 1 }
  if (i > m) {
    for (k = j; k <= n; k++) if (PB[k] != "**") return 0
    PMEMO[key] = 1
    return 1
  }
  if (j > n) {
    for (k = i; k <= m; k++) if (PA[k] != "**") return 0
    PMEMO[key] = 1
    return 1
  }
  if (PA[i] == "**" || PB[j] == "**") {
    if (pathRec(i + 1, j, m, n)) { PMEMO[key] = 1; return 1 }
    if (pathRec(i, j + 1, m, n)) { PMEMO[key] = 1; return 1 }
    return 0
  }
  if (!segX(PA[i], PB[j])) return 0
  if (pathRec(i + 1, j + 1, m, n)) { PMEMO[key] = 1; return 1 }
  return 0
}

BEGIN {
  PROG   = "glob-overlap.sh"
  STDERR = "cat 1>&2"

  na = load(ARGV[1], GA)
  nb = load(ARGV[2], GB)

  found = 0
  for (i = 1; i <= na; i++) {
    for (j = 1; j <= nb; j++) {
      if (pathX(GA[i], GB[j])) {
        printf "%s\t%s\n", GA[i], GB[j]
        found = 1
      }
    }
  }
  exit (found ? 1 : 0)
}
' "$1" "$2" || status=$?

exit "$status"
