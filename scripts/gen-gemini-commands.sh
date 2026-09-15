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
#   gen-gemini-commands.sh <skill>...   regenerate just these
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

canonical_ids() {
  awk '/BEGIN CANONICAL-IDS/{f=1;next} /END CANONICAL-IDS/{f=0} f' "$MAP" \
    | tr -d '`' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -E '^[a-z][a-z0-9-]*$' || true
}

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

cited_ids() {
  grep -oE 'capability:[a-z][a-z0-9-]*' "$1" | sed 's/^capability://' | sort -u || true
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

# existing_description <toml> — reuse the hand-written description line
existing_description() {
  [ -f "$1" ] || return 0
  head -1 "$1" | grep -q '^description = ' && head -1 "$1" || true
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
    note "$skill: no existing description line in $toml — add one by hand first"
    return 1
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

# every skill that already has a toml
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
  note "all embedded Gemini commands match their SKILL.md"
fi

exit "$rc"
