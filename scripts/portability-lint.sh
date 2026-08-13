#!/usr/bin/env bash
#
# portability-lint.sh — enforce the runtime portability contract
# =============================================================================
#
# PURPOSE
#   `references/runtime-tools.md` says skill bodies must name CAPABILITIES, never
#   runtime tool names. That rule already existed in AGENT.md and every skill
#   violated it — a written rule with no mechanical check is how it failed. This
#   script is the check.
#
# WHAT IT CHECKS (only for skills listed in references/converted-skills.md)
#   1. No imperative runtime tool call sites  — "use the Read tool", "Agent(",
#      "subagent_type=", "${CLAUDE_PLUGIN_ROOT}". BARE MENTIONS ARE ALLOWED:
#      check-harness legitimately names Claude Code tools because auditing Claude
#      Code sessions is its subject matter.
#   2. Every cited `capability:<id>` exists in the map's CANONICAL-IDS block.
#   3. Each SKILL.md opens with the mandatory runtime-tools.md read line.
#   4. Every id in the converted-list's required-procedure-ids column still
#      appears in the skill — catches a pinned step rewritten back into prose.
#
# WHAT IS OUT OF SCOPE (deliberately)
#   - Frontmatter. Claude Code enforces real tool gating from `allowed-tools:` /
#     `tools:`; agy ignores frontmatter, and the analyzer `tools:` list is
#     stripped at runtime by the spawn-named-checker procedure.
#   - commands/*.md  — Claude Code-only entry points; agy never loads them.
#   - scripts/       — executed, not read as model instructions.
#   - Unlisted skills — rollout is incremental; the gate must be green on day one.
#
# USAGE
#   portability-lint.sh <file>...    lint specific files
#   portability-lint.sh --sweep      lint every listed skill (full corpus)
#   portability-lint.sh --hook       PreToolUse mode: reads hook JSON on stdin
#
# EXIT
#   0  clean (or not applicable)
#   1  violations found          (file / --sweep mode)
#   2  block the write           (--hook mode only; stderr is shown to the user)
#
# harness-ops has no CI, so --sweep is run by a human via run-tests.sh, and
# --hook catches regressions at the moment of writing.

set -eu

LC_ALL=C
export LC_ALL

# `pwd -P` is load-bearing, not style. This repo ships `plugins/harness-ops -> ../`
# for marketplace path resolution, so ${CLAUDE_PLUGIN_ROOT} can be the SYMLINK
# spelling. With logical `pwd`, REPO_ROOT would become <repo>/plugins/harness-ops
# and the hook's `case "$path" in "$REPO_ROOT"/*` guard would reject every real
# repo file — the gate would silently no-op instead of blocking.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
MAP="$REPO_ROOT/references/runtime-tools.md"
LIST="$REPO_ROOT/references/converted-skills.md"

VIOLATIONS=0

note() { printf '%s\n' "$*" >&2; }

# violation() only PRINTS. Counting is done by the caller, because
# check_imperative reports from inside a pipeline subshell where an increment
# would be lost — so every caller counts explicitly and none of them double.
violation() { printf '  %s\n' "$*" >&2; }

# --------------------------------------------------------------------------
# map + list loading
# --------------------------------------------------------------------------

canonical_ids() {
  [ -f "$MAP" ] || return 0
  awk '/BEGIN CANONICAL-IDS/{f=1;next} /END CANONICAL-IDS/{f=0} f' "$MAP" \
    | tr -d '`' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -E '^[a-z][a-z0-9-]*$' || true
}

# listed_skills — one skill name per line
listed_skills() {
  [ -f "$LIST" ] || return 0
  awk -F'|' '/^\| *[a-z][a-z0-9-]* *\|/ {gsub(/^ +| +$/,"",$2); if ($2 != "skill") print $2}' "$LIST"
}

# required_ids <skill> — comma-separated column, normalized to one id per line
required_ids() {
  [ -f "$LIST" ] || return 0
  awk -F'|' -v s="$1" '
    /^\| *[a-z][a-z0-9-]* *\|/ {
      gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$3)
      if ($2 == s && $3 != "-") { n=split($3, a, ","); for (i=1;i<=n;i++) { gsub(/^ +| +$/,"",a[i]); print a[i] } }
    }' "$LIST"
}

is_listed() {
  listed_skills | grep -qx "$1"
}

# --------------------------------------------------------------------------
# body extraction — frontmatter is out of scope (see header)
# --------------------------------------------------------------------------

# body_of <file> — content with a leading --- ... --- block removed,
# prefixed with the ORIGINAL line number so violations point at real lines.
body_of() {
  awk '
    NR==1 && $0=="---" { fm=1; next }
    fm==1 && $0=="---" { fm=0; next }
    fm==1 { next }
    { printf "%d:%s\n", NR, $0 }
  ' "$1"
}

# --------------------------------------------------------------------------
# checks
# --------------------------------------------------------------------------

TOOLS='Read|Write|Edit|Grep|Glob|Bash|AskUserQuestion|Agent|Task|TaskCreate|TaskUpdate|PushNotification|ScheduleWakeup|CronCreate|WebFetch|WebSearch|SlashCommand'

# Instruction-shaped usage only. A BARE MENTION is deliberately not matched:
# coherence-audit says "no `Agent` tool" to describe a failure mode, and
# check-harness names Claude Code tools because auditing them is its subject
# matter. Flagging those would false-positive on the very skills this protects.
# So a match needs either call syntax `Tool(` or an imperative verb in front.
# "with" is deliberately absent: "sessions with Agent calls" is a metric
# definition, not an instruction, and check-harness is full of them.
IMPERATIVE='[Uu]se|[Uu]sing|[Ii]nvoke|[Ii]nvoking|[Cc]all|[Cc]alling|[Rr]un|[Rr]unning|[Ss]pawn|[Ss]pawning|[Vv]ia'

check_imperative() {
  file="$1"; hits=""
  # Call syntax must start a line (optionally indented). A real spawn is written
  # as a standalone block; `Bash(npm test)` inside a sentence is check-harness
  # REPORTING a detected session pattern, which must not be flagged.
  hits=$(body_of "$file" | grep -nE \
    "(^[0-9]+:[[:space:]]*(${TOOLS})\()|((${IMPERATIVE}) (the )?\`?(${TOOLS})\`?( tool)?\b)" \
    || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | while IFS= read -r h; do
      violation "imperative tool call site: ${h#*:}"
    done
  fi

  # `subagent_type:` / `= ` as an ARGUMENT is a call; `Agent.subagent_type` is a
  # JSONL field name that session-pattern-analyzer counts. Only the former.
  extra=$(body_of "$file" | grep -nE '(^[0-9]+:[[:space:]]*subagent_type[[:space:]]*[:=])|\$\{CLAUDE_PLUGIN_ROOT\}' || true)
  if [ -n "$extra" ]; then
    printf '%s\n' "$extra" | while IFS= read -r h; do
      violation "runtime-specific token (use capability:spawn-named-checker / capability:resolve-harness-root): ${h#*:}"
    done
  fi

  # subshell pipelines can't mutate VIOLATIONS in bash 3.2 — recount here
  n1=$(printf '%s' "$hits" | grep -c . || true)
  n2=$(printf '%s' "$extra" | grep -c . || true)
  VIOLATIONS=$((VIOLATIONS + n1 + n2))
}

check_cited_ids() {
  file="$1"
  cited=$(grep -oE 'capability:[a-z][a-z0-9-]*' "$file" | sed 's/^capability://' | sort -u || true)
  [ -n "$cited" ] || return 0
  known=$(canonical_ids)
  for id in $cited; do
    if ! printf '%s\n' "$known" | grep -qx "$id"; then
      violation "unmapped capability id \`capability:$id\` (not in references/runtime-tools.md)"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done
}

check_map_read_line() {
  file="$1"
  if ! head -60 "$file" | grep -q 'runtime-tools\.md'; then
    violation "missing mandatory map-read line (must reference ../../references/runtime-tools.md near the top)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
}

check_required_ids() {
  skill="$1"; file="$2"
  for id in $(required_ids "$skill"); do
    if ! grep -q "capability:$id" "$file"; then
      violation "required procedure id \`capability:$id\` no longer cited (converted-skills.md declares it)"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done
}

# --------------------------------------------------------------------------
# dispatch: is this path covered, and which skill owns it?
# --------------------------------------------------------------------------

# owning_skill <relpath> — echoes the skill name, or nothing if not covered
owning_skill() {
  case "$1" in
    skills/*/SKILL.md|skills/*/references/*.md)
      printf '%s' "$1" | cut -d/ -f2
      ;;
    agents/*.md)
      # analyzer bodies are covered surface only while a listed skill spawns them
      if listed_skills | while read -r s; do required_ids "$s"; done | grep -qx 'spawn-named-checker'; then
        printf 'agents'
      fi
      ;;
  esac
}

# lint_file <path-for-scope> [content-file] [full|fragment]
#
# `path-for-scope` decides coverage and which skill owns it. `content-file` is
# the text actually linted — for a PreToolUse hook that is the PENDING write,
# not what is on disk. Linting disk state at PreToolUse would only ever catch a
# file that is ALREADY dirty, i.e. PostToolUse semantics one write late, which
# is exactly what D5 rejected.
#
# `fragment` means we only have the replacement text, not the whole resulting
# file, so whole-file checks (map-read line, required ids) are skipped — they
# would false-positive on every partial edit.
lint_file() {
  abs="$1"
  src="${2:-$1}"
  mode="${3:-full}"
  case "$abs" in
    "$REPO_ROOT"/*) rel="${abs#"$REPO_ROOT"/}" ;;
    *) return 0 ;;                      # outside this repo — never our business
  esac
  [ -f "$src" ] || return 0

  skill=$(owning_skill "$rel")
  [ -n "$skill" ] || return 0           # not a covered artifact

  if [ "$skill" != "agents" ] && ! is_listed "$skill"; then
    return 0                            # unconverted — not gated yet
  fi

  before=$VIOLATIONS
  check_imperative "$src"
  check_cited_ids "$src"
  if [ "$mode" = "full" ]; then
    case "$rel" in
      skills/*/SKILL.md)
        check_map_read_line "$src"
        check_required_ids "$skill" "$src"
        ;;
    esac
  fi
  if [ "$VIOLATIONS" -gt "$before" ]; then
    note "FAIL  $rel"
  fi
}

# --------------------------------------------------------------------------
# modes
# --------------------------------------------------------------------------

mode="${1:---help}"

case "$mode" in
  --sweep)
    note "portability sweep — listed skills only"
    for s in $(listed_skills); do
      f="$REPO_ROOT/skills/$s/SKILL.md"
      [ -f "$f" ] || { violation "listed skill has no SKILL.md: $s"; VIOLATIONS=$((VIOLATIONS+1)); continue; }
      lint_file "$f"
      for r in "$REPO_ROOT/skills/$s/references"/*.md; do
        [ -f "$r" ] && lint_file "$r"
      done
    done
    if listed_skills | while read -r s; do required_ids "$s"; done | grep -qx 'spawn-named-checker'; then
      for a in "$REPO_ROOT/agents"/*.md; do
        [ -f "$a" ] && lint_file "$a"
      done
    fi
    [ "$VIOLATIONS" -eq 0 ] && note "sweep clean" || note "sweep: $VIOLATIONS violation(s)"
    [ "$VIOLATIONS" -eq 0 ] || exit 1
    ;;

  --hook)
    payload=$(cat)
    path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
    [ -n "$path" ] || exit 0
    # Canonicalise the INCOMING path too — it may arrive via the symlink spelling
    # even when REPO_ROOT is physical.
    pdir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || exit 0
    path="$pdir/$(basename "$path")"
    case "$path" in
      "$REPO_ROOT"/*) : ;;
      *) exit 0 ;;                      # another project — this hook must no-op
    esac

    # Lint the PENDING write, not the disk. Write carries the whole new file in
    # `content`; Edit carries `old_string`/`new_string`, so reconstruct the
    # post-write text when the file exists — otherwise fall back to linting just
    # the replacement fragment (content checks only).
    tmpf=$(mktemp "${TMPDIR:-/tmp}/portability-lint.XXXXXX")
    trap 'rm -f "$tmpf"' EXIT INT TERM
    hmode=$(python3 - "$payload" "$path" "$tmpf" <<'PY' 2>/dev/null || echo disk
import json, sys

payload, path, out = sys.argv[1], sys.argv[2], sys.argv[3]
ti = json.loads(payload).get("tool_input", {})

def emit(text, mode):
    open(out, "w").write(text)
    print(mode)
    sys.exit(0)

# Write: the payload IS the whole new file.
if "content" in ti:
    emit(ti["content"], "full")

try:
    src = open(path).read()
except OSError:
    src = None

# Edit / MultiEdit: fold every replacement onto the current text, in order.
# MultiEdit carries `edits[]` and no top-level new_string — missing that branch
# meant the payload fell through to disk-linting and the write sailed past.
edits = ti.get("edits")
if not edits and "new_string" in ti:
    edits = [ti]

if edits:
    if src is not None:
        ok = True
        cur = src
        for e in edits:
            old, new = e.get("old_string", ""), e.get("new_string", "")
            if not old or old not in cur:
                ok = False
                break
            # honour replace_all — patching only the first occurrence left every
            # other insertion unlinted.
            cur = cur.replace(old, new) if e.get("replace_all") else cur.replace(old, new, 1)
        if ok:
            emit(cur, "full")
    # Could not reconstruct: lint just the inserted text. Content checks only —
    # whole-file checks would false-positive on a partial edit.
    emit("\n".join(e.get("new_string", "") for e in edits), "fragment")

sys.exit(1)
PY
)
    if [ "$hmode" = "disk" ]; then
      cp "$path" "$tmpf" 2>/dev/null || exit 0   # nothing pending; lint disk
      hmode=full
    fi

    lint_file "$path" "$tmpf" "$hmode"
    if [ "$VIOLATIONS" -gt 0 ]; then
      note ""
      note "Blocked by the portability contract (references/runtime-tools.md)."
      note "Skill bodies name capabilities, not runtime tool names."
      exit 2
    fi
    exit 0
    ;;

  --help|-h)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;

  *)
    for f in "$@"; do
      case "$f" in
        /*) lint_file "$f" ;;
        *)  lint_file "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" ;;
      esac
    done
    [ "$VIOLATIONS" -eq 0 ] || exit 1
    ;;
esac

exit 0
