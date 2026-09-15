#!/usr/bin/env bash
#
# gen-gemini-commands.sh — regenerate .gemini/commands/harness-ops/<skill>.toml
# =============================================================================
#
# PURPOSE
#   The Gemini CLI commands EMBED a copy of each skill's SKILL.md (README:
#   "the .toml files embed a copy of each skill's SKILL.md, so they must be
#   regenerated when a skill changes"). That rule was enforced by hand and drifted:
#   worktree.toml was regenerated while context-audit.toml kept an older body, so
#   the two runtimes executed different procedures for the same command. This
#   script is the mechanical version of that rule.
#
# WHY A PREAMBLE IS INJECTED
#   A SKILL.md addresses its references RELATIVE TO ITS OWN DIRECTORY
#   (`../../references/runtime-tools.md`) — the path rule in runtime-tools.md.
#   That anchor is real for Claude Code and for agy, which both load the skill
#   from skills/<name>/. It does NOT exist for a Gemini CLI command: the body
#   arrives as prompt text, the file is read from ~/.gemini/commands/harness-ops/,
#   and the cwd is the USER'S project. `../../references/...` there resolves to
#   ~/references/... and does not exist.
#
#   Embedding the mandatory "read ../../references/runtime-tools.md before
#   executing any step" line with no way to satisfy it leaves the agent stuck on a
#   precondition it cannot meet. So the generator prepends a block that RESOLVES
#   the harness-ops root at runtime and states what every `../../` path means.
#
# USAGE
#   gen-gemini-commands.sh              regenerate every toml that has a SKILL.md
#   gen-gemini-commands.sh <skill>...   regenerate just these, CREATING the toml
#                                       if it does not exist yet (the description
#                                       is derived from the SKILL.md frontmatter
#                                       for review; a hand-written one is kept)
#   gen-gemini-commands.sh --check      exit 1 if any toml is stale (no writes)
#
# EXIT
#   0  written / up to date
#   1  --check found stale output, or a requested skill does not exist

set -eu

LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
CMD_DIR="$ROOT/.gemini/commands/harness-ops"
MAP="$ROOT/references/runtime-tools.md"

note() { printf '%s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# determinism-critical classification
#
# CANONICAL-IDS lists every id. The "General capabilities" table is explicitly
# `determinism-critical: false`; every other id in the canonical list is a pinned
# or divergent procedure, i.e. true. Deriving it this way means adding a
# capability to the map cannot silently mis-classify it here.
# ---------------------------------------------------------------------------

# canonical_ids and cited_ids live in scripts/lib/capability-map.sh — the linter
# needs the same two readers, and two copies of one parser drift apart.
. "$SCRIPT_DIR/lib/capability-map.sh"

# ids in the General capabilities table (determinism-critical: false)
general_ids() {
  awk '
    /^## General capabilities/ {f=1; next}
    f && /^## / {f=0}
    f && /^\| *`[a-z]/ {
      line=$0
      sub(/^\| *`/, "", line)
      sub(/`.*$/, "", line)
      print line
    }
  ' "$MAP"
}

critical_ids() {
  gen=$(general_ids)
  canonical_ids | while read -r id; do
    printf '%s\n' "$gen" | grep -qx "$id" || printf '%s\n' "$id"
  done
}

# cited_critical <skill-md> — the cited ids that are determinism-critical
cited_critical() {
  crit=$(critical_ids)
  cited_ids "$1" | while read -r id; do
    printf '%s\n' "$crit" | grep -qx "$id" && printf '%s\n' "$id"
  done
  true
}

# ---------------------------------------------------------------------------
# preamble
# ---------------------------------------------------------------------------

emit_preamble() {
  skill="$1"; crit="$2"
  cat <<PRE
<!-- GENERATED from skills/${skill}/SKILL.md by scripts/gen-gemini-commands.sh.
     Do not edit this copy — edit the SKILL.md and regenerate. -->

> **Path anchor — resolve this before step 1.** Everything below this block is a verbatim copy of
> \`skills/${skill}/SKILL.md\` from a **harness-ops checkout**. Its relative paths are written
> against \`skills/${skill}/\`, which is **not** your working directory: you were loaded from
> \`~/.gemini/commands/harness-ops/\` and your cwd is the user's own project. So a literal
> \`../../references/x.md\` resolves to \`~/references/x.md\` and does not exist. **Resolve the
> checkout root first**, then read every \`../../\` path relative to it:
>
> \`\`\`bash
> for c in "\$HOME/.gemini/commands/harness-ops" "./.gemini/commands/harness-ops"; do
>   r=\$(cd -P "\$c/../../.." 2>/dev/null && pwd -P) || continue
>   [ -f "\$r/references/runtime-tools.md" ] && [ -d "\$r/skills/${skill}" ] && { echo "\$r"; break; }
> done
> \`\`\`
>
> This works through the symlink the README prescribes
> (\`ln -s /path/to/harness-ops/.gemini/commands/harness-ops ~/.gemini/commands/harness-ops\`), and
> also when Gemini CLI is run from inside the harness-ops checkout itself. With \`<root>\` in hand,
> \`../../references/runtime-tools.md\` means \`<root>/references/runtime-tools.md\`, and the same
> substitution applies to every other \`../../\` path in the body.
PRE

  if [ -n "$crit" ]; then
    cat <<PRE
>
> **If no candidate validates, halt** — say \`unresolved: harness root did not validate\`. This
> skill cites pinned, determinism-critical procedures ($(printf '%s' "$crit" | tr '\n' ' ' | sed 's/ $//')),
> and the map is the only place they are defined. Guessing at one is the substitution the
> procedure ids exist to prevent.
PRE
  else
    cat <<'PRE'
>
> **If no candidate validates, do not halt.** Every capability this skill cites is
> `determinism-critical: false` — a plain file / shell / ask-the-user action whose name differs
> per runtime but whose outcome does not depend on the map. Say that the map could not be located,
> then carry on, reading each `` `capability:<id>` `` as your own runtime's equivalent (the shell
> capability is `run-command`; prompting the user is `ask-user`). Halting here would strand the
> user over a reference file, not a real precondition.
PRE
  fi
  printf '\n'
}

# ---------------------------------------------------------------------------
# generation
# ---------------------------------------------------------------------------

# existing_description <toml> — reuse the hand-written description line.
# The curated one-liners in the tomls are shorter and better than anything
# derivable, so an existing line always wins.
existing_description() {
  [ -f "$1" ] || return 0
  head -1 "$1" | grep -q '^description = ' && head -1 "$1" || true
}

# derived_description <skill-md> — BOOTSTRAP fallback for a toml that does not
# exist yet. Flattens the frontmatter `description:` (block scalar or inline) to
# one line and truncates it on a word boundary.
#
# Truncation, not first-sentence detection, is deliberate: these descriptions are
# dense with paths, so the obvious "cut at the first '. '" rule cuts
# `specs/<feature>/spec.md files` in half at the `.md`. A predictable trim the
# author then edits beats a clever rule that is wrong in a way nobody notices.
derived_description() {
  [ -f "$1" ] || return 0
  awk '
    NR==1 && $0=="---"        { fm=1; next }
    fm && /^---[[:space:]]*$/ { exit }
    fm && /^description:/ {
      line=$0; sub(/^description:[[:space:]]*/, "", line)
      if (line ~ /^[|>]-?[[:space:]]*$/) { blk=1; next }
      printf "%s", line; exit
    }
    blk && /^[A-Za-z_-]+:/ { exit }          # next frontmatter key closes the block
    blk {
      sub(/^[[:space:]]+/, "", $0)
      if ($0 != "") printf "%s ", $0
    }
  ' "$1" \
    | sed -e 's/^"//' -e 's/"$//' -e 's/[[:space:]]\{1,\}/ /g' -e 's/[[:space:]]*$//' \
    | awk '{
        if (length($0) <= 160) { print; exit }
        out=""
        n=split($0, w, " ")
        for (i=1; i<=n; i++) {
          if (length(out) + length(w[i]) + 1 > 160) break
          out = (out == "" ? w[i] : out " " w[i])
        }
        print out
      }' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

generate() {
  skill="$1"
  md="$ROOT/skills/$skill/SKILL.md"
  toml="$CMD_DIR/$skill.toml"

  if [ ! -f "$md" ]; then
    note "no SKILL.md for '$skill'"
    return 1
  fi
  if grep -q "'''" "$md"; then
    note "$skill: SKILL.md contains ''' — cannot embed in a TOML literal block"
    return 1
  fi

  desc=$(existing_description "$toml")
  if [ -z "$desc" ]; then
    body=$(derived_description "$md")
    if [ -z "$body" ]; then
      note "$skill: no description in $toml and none in the SKILL.md frontmatter"
      return 1
    fi
    desc="description = \"$body\""
    note "$skill: bootstrapped description from SKILL.md frontmatter — review and refine it"
  fi

  crit=$(cited_critical "$md")

  {
    printf '%s\n' "$desc"
    printf "prompt = '''\n"
    emit_preamble "$skill" "$crit"
    cat "$md"
    printf '\nUser arguments: {{args}}\n'
    printf "'''\n"
  }
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

# every skill that already has a toml.
#
# Deliberately NOT every skill with a SKILL.md: a bare run and `--check` must not
# start demanding tomls for skills nobody has decided to expose as Gemini
# commands. Bootstrapping a new one is an explicit act — name the skill.
all_skills() {
  for f in "$CMD_DIR"/*.toml; do
    [ -f "$f" ] || continue
    b=$(basename "$f" .toml)
    [ -f "$ROOT/skills/$b/SKILL.md" ] && printf '%s\n' "$b"
  done
}

mode=write
case "${1:-}" in
  --check) mode=check; shift ;;
  --help|-h) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

if [ "$#" -gt 0 ]; then
  targets=$(printf '%s\n' "$@")
else
  targets=$(all_skills)
fi

rc=0
stale=0
for s in $targets; do
  toml="$CMD_DIR/$s.toml"
  out=$(generate "$s") || { rc=1; continue; }
  if [ "$mode" = check ]; then
    if [ ! -f "$toml" ] || ! printf '%s\n' "$out" | diff -q - "$toml" >/dev/null 2>&1; then
      note "STALE  .gemini/commands/harness-ops/$s.toml"
      stale=$((stale + 1))
    fi
  else
    printf '%s\n' "$out" > "$toml"
    note "wrote  .gemini/commands/harness-ops/$s.toml"
  fi
done

if [ "$mode" = check ]; then
  if [ "$stale" -gt 0 ]; then
    note ""
    note "$stale toml file(s) out of date — run scripts/gen-gemini-commands.sh"
    exit 1
  fi
  # Only claim a clean sweep when nothing failed to generate. A skill that could
  # not be generated at all leaves `stale` at 0, so the old unconditional line
  # printed "all ... match" next to its own error and exited 1 — a summary that
  # contradicted the exit status is worse than no summary.
  if [ "$rc" -eq 0 ]; then
    note "all embedded Gemini commands match their SKILL.md"
  else
    note "checked what could be generated; some skills failed above"
  fi
fi

exit "$rc"
