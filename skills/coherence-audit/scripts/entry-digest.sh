#!/usr/bin/env bash
#
# entry-digest.sh — the per-entry digest stamped into a generated spec
# =============================================================================
#
# PURPOSE
#   ONE shared implementation of the partition-manifest entry digest that
#   `decompose` stamps into each generated spec as
#
#       <!-- decompose-entry: <feature-id> @ sha256:<digest> -->
#
#   on line 1 of `specs/<feature-id>/spec.md`.
#
#   The STAMPING side (right after `specify mode: batch` returns) and the
#   VERIFYING side (the next resume, deciding "did this entry change?") MUST
#   both obtain the digest by running THIS script. Never hand-roll the hash.
#   Because both sides run the same bytes through the same normalization, a
#   FALSE mismatch — producer and verifier disagreeing about an entry nobody
#   edited — cannot arise between two callers that BOTH run this script.
#   That guarantee is conditional, not structural: nothing in the harness
#   detects a caller that hand-rolls the hash or skips the check entirely
#   (spec Known Gap 1 — no runtime enforcement of a skill instruction).
#   (Modelled on harness-factory `skills/generate-team/references/
#   checksum-normalization.md` + `scripts/checksum.sh`, which exist for exactly
#   the same reason.)
#
# USAGE
#   entry-digest.sh <partition-manifest.md> <feature-id>
#   entry-digest.sh --canonical <partition-manifest.md> <feature-id>
#
#     digest=$(entry-digest.sh specs/login-stack/partition-manifest.md auth)
#
#   Input is the MANIFEST PATH + a FEATURE-ID, not a pre-sliced single-entry
#   file. That is the simpler design here because it is the only one that keeps
#   the contract single-sourced: if the caller had to slice one entry out first,
#   the slicing rules would become a second, unwritten normalization step that
#   the stamper and the verifier could implement differently — reintroducing the
#   exact false-mismatch this script exists to make impossible. Every real call
#   site already holds the manifest path and a feature-id.
#
#   `--canonical` prints the canonical pre-hash text instead of the digest. It
#   exists so a human debugging an unexpected drift report can see the exact
#   bytes being hashed. It changes nothing about the digest.
#
#   stdout: the bare lowercase sha256 hex digest and nothing else, so it is safe
#           to capture with `$(...)`.  exit 0.
#   errors: message on stderr, stdout empty, exit 2 — wrong argument count,
#           missing/unreadable/directory path, feature-id not present in the
#           manifest, or no sha256 tool available.
#
# WHAT IS HASHED — HUMAN-OWNED FIELDS ONLY  (D20; this exclusion IS the design)
#   INCLUDED : feature-id, declared-surface (the glob list), depends_on,
#              accept-seed.
#   EXCLUDED : `state:` and `pre-approved-batch:`  — and anything else in the
#              entry.
#
#   Why the exclusion is load-bearing: `state:` and `pre-approved-batch:` are
#   MACHINE-flipped on every normal run (D12, D19). Hashing them would change
#   the digest on every run, make every entry read as "changed" on the next
#   resume, and render D19's cheap path ("entries that did not change are not
#   re-gated") unreachable — turning every resume into a full re-gate plus a
#   full re-merge. The digest must be a function of only what a HUMAN can edit.
#
#   Fields are excluded by WHITELIST, not by blacklist: any manifest line inside
#   the entry that is not one of the four included fields is ignored. So a later
#   machine-owned field added to the entry cannot silently start perturbing the
#   digest.
#
# CANONICAL NORMALIZATION — THIS BLOCK IS THE CONTRACT
#   The digest is sha256 over the following text, built in exactly this order:
#
#   1. FIXED FIELD ORDER. Always, regardless of the order in the manifest:
#          feature-id:      <id>
#          declared-surface: <glob>       (0..n lines)
#          depends_on:      <feature-id>  (0..n lines)
#          accept-seed:     <text>
#      One `<field>: <value>` line per value. `feature-id:` and `accept-seed:`
#      are ALWAYS emitted (an absent or empty accept-seed emits the line with an
#      empty value, so "absent" and "present but empty" hash identically). A
#      list field with no values emits no lines. A newline can never occur
#      inside a value, so the encoding is unambiguous.
#
#   2. LIST ORDER IS SORTED, not source order. Both `declared-surface` globs and
#      `depends_on` ids are sorted in BYTE order (`LC_ALL=C`, exported below, so
#      the result cannot depend on the user's locale). Reordering the bullets in
#      the manifest is not a semantic change and must not read as drift.
#      Duplicates are NOT collapsed — a duplicate entry is a real edit, and
#      "sorted" is the only ordering rule the contract states.
#
#   3. WHITESPACE IS COLLAPSED. Every value has leading/trailing whitespace
#      stripped and internal runs of spaces/tabs collapsed to a single space.
#      Re-wrapping or re-indenting the manifest is not a semantic change.
#
#   4. LINE ENDINGS ARE LF. A trailing `\r` is stripped from every input line
#      (CRLF tolerance), and the canonical text is joined with `\n`.
#
#   5. NO TRAILING-NEWLINE AMBIGUITY. The canonical text ends with EXACTLY ONE
#      `\n`, whether or not the manifest did.
#
#   6. sha256 of those bytes; lowercase hex.
#
#   Everything else about the manifest is invisible to the digest: the
#   `generated_at:` stamp, the `goal:` line, the `## Shared Decisions` block,
#   other features' entries, comments, and blank lines.
#
# HOW AN ENTRY IS FOUND
#   The `## Features` section only (so a `### SD1: …` heading under
#   `## Shared Decisions` can never be mistaken for a feature). Inside it, the
#   entry is the `### <feature-id>` heading and every line up to the next
#   `###`/`##` heading or EOF. If a feature-id appears twice, the FIRST entry
#   wins. Glob bullets are the bullets indented DEEPER than the
#   `- declared-surface:` line that opens them, which is what separates them
#   from the entry's own `- <field>:` bullets at any base indentation.
#
# PORTABILITY
#   bash + POSIX awk only; no GNU-isms. Prefers `shasum -a 256` (present on
#   macOS/darwin), falls back to `sha256sum` (typical on Linux). Both produce
#   byte-identical digests for identical input. Verified on macOS/Darwin
#   (bash 3.2 + BSD one-true-awk).
#
# TESTS
#   bash skills/coherence-audit/scripts/run-tests.sh
#
set -eu

# Byte-order sorting and byte-order string comparison, independent of the
# caller's locale. Load-bearing for normalization step 2.
LC_ALL=C
export LC_ALL

PROG="entry-digest.sh"

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
  err "usage: $PROG [--canonical] <partition-manifest.md> <feature-id>"
}

# --- argument parsing ------------------------------------------------------
show_canonical=0
if [ "$#" -gt 0 ] && [ "$1" = "--canonical" ]; then
  show_canonical=1
  shift
fi

if [ "$#" -ne 2 ]; then
  usage
  exit 2
fi

manifest="$1"
feature="$2"

if [ -z "$feature" ]; then
  err "empty feature-id"
  exit 2
fi
if [ ! -e "$manifest" ]; then
  err "no such file: $manifest"
  exit 2
fi
if [ -d "$manifest" ]; then
  err "is a directory, expected a manifest file: $manifest"
  exit 2
fi
if [ ! -r "$manifest" ]; then
  err "file not readable: $manifest"
  exit 2
fi

# --- build the canonical text ----------------------------------------------
# awk exit codes: 0 = ok, 3 = feature-id not found in the manifest.
rc=0
canonical=$(awk -v want="$feature" '
function trim(s) {
  sub(/^[ \t]+/, "", s)
  sub(/[ \t]+$/, "", s)
  return s
}
# collapse(): normalization step 3 — strip ends, collapse internal runs.
function collapse(s) {
  gsub(/[ \t]+/, " ", s)
  return trim(s)
}
# byte-order insertion sort (lists are tiny; avoids a sort(1) pipeline and any
# locale dependence beyond the LC_ALL=C exported by the wrapper)
function isort(arr, n,   i, j, v) {
  for (i = 2; i <= n; i++) {
    v = arr[i]
    j = i - 1
    while (j >= 1 && arr[j] > v) { arr[j + 1] = arr[j]; j-- }
    arr[j + 1] = v
  }
}

BEGIN {
  inFeatures = 0   # inside the `## Features` section
  inEntry    = 0   # inside the wanted `### <feature-id>` entry
  done       = 0   # the wanted entry has been fully read (first one wins)
  found      = 0
  inSurface  = 0   # reading the declared-surface bullet list of that entry
  dsIndent   = -1
  nGlob      = 0
  nDep       = 0
  seed       = ""
}

{
  line = $0
  sub(/\r$/, "", line)                    # normalization step 4: CRLF tolerance

  # --- section / entry tracking --------------------------------------------
  if (line ~ /^##[ \t]/ && line !~ /^###/) {
    if (inEntry) { done = 1; inEntry = 0 }
    hdr = line
    sub(/^##[ \t]+/, "", hdr)
    inFeatures = (hdr ~ /^Features([ \t]|$)/)
    inSurface = 0
    next
  }
  if (line ~ /^###[ \t]/) {
    if (inEntry) { done = 1; inEntry = 0 }
    inSurface = 0
    if (inFeatures && !done) {
      name = line
      sub(/^###[ \t]+/, "", name)
      name = trim(name)
      if (name == want) { inEntry = 1; found = 1 }
    }
    next
  }
  if (!inEntry) next

  # --- inside the wanted entry ---------------------------------------------
  if (line ~ /^[ \t]*$/) next             # blank lines carry nothing

  # is this a bullet line, and at what indent?
  if (line !~ /^[ \t]*-[ \t]*/) { inSurface = 0; next }
  match(line, /^[ \t]*/)
  indent = RLENGTH
  body = line
  sub(/^[ \t]*-[ \t]*/, "", body)

  # a declared-surface glob is a bullet indented DEEPER than the
  # `- declared-surface:` bullet that opened the list
  if (inSurface && indent > dsIndent) {
    g = collapse(body)
    if (g != "") { nGlob++; globs[nGlob] = g }
    next
  }
  inSurface = 0

  if (body ~ /^declared-surface:/) {
    inSurface = 1
    dsIndent  = indent
    rest = body
    sub(/^declared-surface:/, "", rest)
    rest = collapse(rest)                 # tolerate an inline single glob
    if (rest != "") { nGlob++; globs[nGlob] = rest }
    next
  }
  if (body ~ /^depends_on:/) {
    rest = body
    sub(/^depends_on:/, "", rest)
    rest = trim(rest)
    sub(/^\[/, "", rest)
    sub(/\]$/, "", rest)
    k = split(rest, parts, ",")
    for (i = 1; i <= k; i++) {
      d = collapse(parts[i])
      if (d != "") { nDep++; deps[nDep] = d }
    }
    next
  }
  if (body ~ /^accept-seed:/) {
    rest = body
    sub(/^accept-seed:/, "", rest)
    seed = collapse(rest)
    next
  }
  # Every other field (state:, pre-approved-batch:, anything a later change
  # adds) is IGNORED — the whitelist above is the contract.
  next
}

END {
  if (!found) exit 3
  isort(globs, nGlob)                     # normalization step 2
  isort(deps, nDep)
  printf "feature-id: %s\n", collapse(want)          # normalization step 1
  for (i = 1; i <= nGlob; i++) printf "declared-surface: %s\n", globs[i]
  for (i = 1; i <= nDep;  i++) printf "depends_on: %s\n", deps[i]
  printf "accept-seed: %s\n", seed
}
' "$manifest") || rc=$?

if [ "$rc" -eq 3 ]; then
  err "feature-id not found under '## Features' in $manifest: $feature"
  exit 2
fi
if [ "$rc" -ne 0 ]; then
  err "failed to parse manifest: $manifest"
  exit 2
fi

# `$(...)` strips trailing newlines, so re-append exactly one — normalization
# step 5, which is what makes the digest independent of how the manifest ended.
if [ "$show_canonical" -eq 1 ]; then
  printf '%s\n' "$canonical"
  exit 0
fi

# --- sha256 ----------------------------------------------------------------
if command -v shasum >/dev/null 2>&1; then
  digest=$(printf '%s\n' "$canonical" | shasum -a 256 | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  digest=$(printf '%s\n' "$canonical" | sha256sum | awk '{print $1}')
else
  err "no sha256 tool found (need 'shasum' or 'sha256sum')"
  exit 2
fi

if [ -z "$digest" ]; then
  err "sha256 computation produced no output"
  exit 2
fi

printf '%s\n' "$digest"
