#!/usr/bin/env bash
#
# pilot-verify.sh — run the converted pilot skills under agy, then restore
# =============================================================================
#
# WHY THIS EXISTS
#   `~/.gemini/config/skills.json` registers harness-ops skills by ABSOLUTE PATH,
#   and it points at the main checkout. Verifying unmerged work therefore reads
#   STALE CODE and appears to pass. This script repoints it at the working tree
#   for the duration of one run, then puts it back.
#
#   agy also auto-denies `run_command` in headless `-p` mode, so a pinned-script
#   step would fail for HARNESS reasons and look like a code failure. A SCOPED
#   allow-rule was tried first and did not work: a skill needs the `command`
#   capability long before it reaches a pinned script, so agy denied the
#   capability outright and no skill body ran. The verification run therefore
#   uses time-boxed `--dangerously-skip-permissions` (human-approved); the
#   allow-rules below remain as documentation of what the pilot touches.
#
# BLAST RADIUS — READ THIS
#   Both files are MACHINE-GLOBAL. While this runs, every agy project on this
#   machine resolves harness-ops skills to this working tree. Restore is
#   unconditional (EXIT/INT/TERM trap), and --check will tell you if a previous
#   run died mid-flight.
#
# USAGE
#   pilot-verify.sh --check     show current state and what would change (no writes)
#   pilot-verify.sh --run       repoint, run the pilot under agy, restore
#   pilot-verify.sh --restore   emergency: restore from the last backup and exit
#
# EXIT
#   0  pilot verified          1  verification failed        2  usage/precondition error

set -eu

LC_ALL=C
export LC_ALL

# `pwd -P` for the same reason as portability-lint.sh: this repo ships
# `plugins/harness-ops -> ../`, so a logical path would make REPO_ROOT the
# symlink dir and repoint skills.json at the wrong spelling.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)

SKILLS_JSON="$HOME/.gemini/config/skills.json"
AGY_SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
BACKUP_DIR="$HOME/.gemini/.harness-ops-pilot-backup"

PILOT_SKILLS="coherence-audit check-harness"

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { warn "pilot-verify: $*"; exit 2; }

command -v agy >/dev/null 2>&1 || die "agy not found on PATH"
command -v jq  >/dev/null 2>&1 || die "jq not found on PATH"
[ -f "$SKILLS_JSON" ]  || die "not found: $SKILLS_JSON"
[ -f "$AGY_SETTINGS" ] || die "not found: $AGY_SETTINGS"

# ---------------------------------------------------------------------------
# backup / restore — restore must be unconditional and idempotent
# ---------------------------------------------------------------------------

backup() {
  mkdir -p "$BACKUP_DIR"
  cp "$SKILLS_JSON"  "$BACKUP_DIR/skills.json.bak"
  cp "$AGY_SETTINGS" "$BACKUP_DIR/settings.json.bak"
  date +%s > "$BACKUP_DIR/taken-at"
}

restore() {
  rc=$?
  if [ -f "$BACKUP_DIR/skills.json.bak" ]; then
    cp "$BACKUP_DIR/skills.json.bak"  "$SKILLS_JSON"
    cp "$BACKUP_DIR/settings.json.bak" "$AGY_SETTINGS"
    rm -f "$BACKUP_DIR/skills.json.bak" "$BACKUP_DIR/settings.json.bak" "$BACKUP_DIR/taken-at"
    say ""
    say "restored: skills.json and antigravity-cli/settings.json are back to their prior values"
  fi
  exit $rc
}

# ---------------------------------------------------------------------------
# modes
# ---------------------------------------------------------------------------

mode="${1:---check}"

case "$mode" in
  --restore)
    if [ -f "$BACKUP_DIR/skills.json.bak" ]; then
      cp "$BACKUP_DIR/skills.json.bak"  "$SKILLS_JSON"
      cp "$BACKUP_DIR/settings.json.bak" "$AGY_SETTINGS"
      rm -f "$BACKUP_DIR/skills.json.bak" "$BACKUP_DIR/settings.json.bak" "$BACKUP_DIR/taken-at"
      say "restored from backup"
    else
      say "no backup present — nothing to restore (machine is in its normal state)"
    fi
    exit 0
    ;;

  --check)
    say "repo (working tree) : $REPO_ROOT"
    say "skills.json points  : $(jq -r '.entries[].path' "$SKILLS_JSON" | tr '\n' ' ')"
    say "would repoint to    : $REPO_ROOT/skills"
    say "allow-rules now     : $(jq -r '.permissions.allow // [] | join(", ")' "$AGY_SETTINGS")"
    say "would add           : command(bash $REPO_ROOT/skills/coherence-audit/scripts/*)"
    say "trusted workspaces  : $(jq -r '.trustedWorkspaces // [] | join(", ")' "$AGY_SETTINGS")"
    if [ -f "$BACKUP_DIR/skills.json.bak" ]; then
      warn ""
      warn "WARNING: a backup exists from $(cat "$BACKUP_DIR/taken-at" 2>/dev/null || echo '?')."
      warn "A previous run may have died before restoring. Run --restore before anything else."
      exit 1
    fi
    say ""
    say "state is clean. run with --run to verify the pilot."
    exit 0
    ;;

  --run) : ;;
  *) die "unknown mode: $mode (use --check | --run | --restore)" ;;
esac

# ---------------------------------------------------------------------------
# --run
# ---------------------------------------------------------------------------

[ -f "$BACKUP_DIR/skills.json.bak" ] && die "a backup already exists — run --restore first"

# Every listed pilot skill must pass the linter BEFORE we spend a run on it.
if ! "$SCRIPT_DIR/portability-lint.sh" --sweep; then
  die "portability sweep failed — fix the contract violations before verifying"
fi

backup
trap restore EXIT INT TERM

say "repointing skills.json -> $REPO_ROOT/skills"
jq --arg p "$REPO_ROOT/skills" '.entries = [{"path": $p}]' "$SKILLS_JSON" > "$SKILLS_JSON.tmp"
mv "$SKILLS_JSON.tmp" "$SKILLS_JSON"

say "adding scoped allow-rules + trusting the working tree"
jq --arg s "command(bash $REPO_ROOT/skills/coherence-audit/scripts/glob-overlap.sh)" \
   --arg e "command(bash $REPO_ROOT/skills/coherence-audit/scripts/entry-digest.sh)" \
   --arg w "$REPO_ROOT" '
     .permissions.allow = ((.permissions.allow // []) + [$s, $e] | unique)
     | .trustedWorkspaces = ((.trustedWorkspaces // []) + [$w] | unique)
   ' "$AGY_SETTINGS" > "$AGY_SETTINGS.tmp"
mv "$AGY_SETTINGS.tmp" "$AGY_SETTINGS"

# --- confirm agy now sees the working-tree copies ---------------------------
say ""
say "== agy skill discovery =="
listed=$(agy -p "/skills" 2>&1 | grep -cE '^(coherence-audit|check-harness)\b' || true)
if [ "$listed" -ge 2 ]; then
  say "  OK   both pilot skills are discoverable"
else
  warn "  FAIL only $listed of 2 pilot skills discoverable"
  exit 1
fi

# --- R2.2: the converted skills must actually open the map ------------------
say ""
say "== map-read (R2.2) =="
for s in $PILOT_SKILLS; do
  if grep -q 'runtime-tools\.md' "$REPO_ROOT/skills/$s/SKILL.md"; then
    say "  OK   $s cites the runtime map"
  else
    warn "  FAIL $s does not cite the runtime map"; exit 1
  fi
done

say ""
say "== pilot run under agy =="
say "NOTE: this spends model quota. Each skill is invoked non-interactively."
#
# WHY --dangerously-skip-permissions HERE
#   A skill needs the `command` capability long before it reaches a pinned script
#   (resolving a spec set, creating a cache dir). A scoped allow-list therefore
#   denies the capability outright and NO skill body runs — which proves nothing
#   about the conversion, only that the harness never let it start. The set of
#   commands a skill may invoke is open-ended, so enumeration is the wrong shape.
#   Human-approved for this verification run. It is time-boxed to these two
#   invocations, and both mutated config files are already backed up and restored
#   by the trap above regardless of outcome.
say ""
say "--- /harness-ops:coherence-audit (against the 2-spec fixture) ---"
# The fixture gives two INTERSECTING declared surfaces, so the overlap tier has
# real work and the pinned `run-glob-overlap` procedure is actually reached.
# Without it coherence-audit short-circuits on "undeclared surface" and the
# pinned script is never exercised — which proves nothing about R4.1/R4.5.
agy -p "/harness-ops:coherence-audit skills/coherence-audit/scripts/tests/portability-fixture/*/spec.md" \
    --dangerously-skip-permissions --print-timeout 300s 2>&1 | head -50 || true

say ""
say "--- R4.5 cross-runtime parity: pinned script output under agy ---"
# Ask agy to run the SAME pinned script on the SAME inputs and echo raw output,
# so it can be diffed against the Claude Code baseline.
agy -p "Run exactly this command with run_command and print its raw stdout and exit code, nothing else:
bash $REPO_ROOT/skills/coherence-audit/scripts/glob-overlap.sh $REPO_ROOT/skills/coherence-audit/scripts/tests/portability-fixture/a.txt $REPO_ROOT/skills/coherence-audit/scripts/tests/portability-fixture/b.txt" \
    --dangerously-skip-permissions --print-timeout 180s 2>&1 | head -20 || true

say ""
say "--- /harness-ops:check-harness (+ R3.5 registry assertion) ---"
# R3.5 must be answered INSIDE the same agy session: the subagent registry is
# per-session, so a post-hoc query from outside can never see it.
agy -p "/harness-ops:check-harness

After the run completes, additionally report the R3.5 delegation assertion: call manage_subagents
and list every subagent that was DEFINED and INVOKED during this session. State plainly whether
the four named analyzers were genuinely delegated or whether their reports were written in-context." \
    --dangerously-skip-permissions --print-timeout 420s 2>&1 | tail -30 || true

say ""
say "Pilot invoked. Compare the parity output above against the Claude Code baseline,"
say "and read the R3.5 registry statement before treating this as a pass."
exit 0
