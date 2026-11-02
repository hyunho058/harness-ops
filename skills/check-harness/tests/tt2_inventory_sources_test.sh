#!/usr/bin/env bash
# TT2 — acceptance tests for R2.4, R2.10, R2.11 (missing/malformed sources warn,
# dead / used-in-30-days counts, effective-argument echo; spec D5, D2).
# Black box: drives skills/check-harness/scripts/inventory.py through its CLI only,
# with HOME pointed at a fixture directory.
# Run from the repo root: bash skills/check-harness/tests/tt2_inventory_sources_test.sh
set -u

cd "$(dirname "$0")/../../.." || exit 1
export PYTHONDONTWRITEBYTECODE=1
INV="skills/check-harness/scripts/inventory.py"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
T="$(cd "$SCRATCH" && pwd -P)"

FAILS=0

mkskill() { # DIR NAME
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: Fixture skill %s.\n---\n\nBody.\n' "$2" "$2" >"$1/SKILL.md"
}

run_inv() { # CASE_DIR HOME ARGS...
  local c="$1" h="$2"
  shift 2
  ( HOME="$h" python3 "$INV" "$@" >"$c/stdout" 2>"$c/stderr"; echo $? >"$c/rc" )
}

PRE='
import json, os, sys
c = sys.argv[1]
rc = int(open(c + "/rc").read().strip())
out = open(c + "/stdout").read()
err = open(c + "/stderr").read()
try:
    d = json.loads(out)
except Exception as e:
    sys.exit("stdout is not JSON (exit %d): %s; stderr: %s" % (rc, e, err[:400]))
assert rc == 0, "exit %d, want 0; stderr: %s" % (rc, err[:400])
'

check() { # NAME CASE_DIR PYCODE [ARGS...]
  local name="$1" c="$2" code="$3"
  shift 3
  if [ ! -f "$INV" ]; then
    echo "FAIL - $name: $INV does not exist"; FAILS=$((FAILS + 1)); return
  fi
  if python3 -c "$PRE$code" "$c" "$@" 2>"$c/assert.err"; then
    echo "ok   - $name"
  else
    echo "FAIL - $name: $(tail -n 3 "$c/assert.err" | tr '\n' ' ')"
    FAILS=$((FAILS + 1))
  fi
}

# ---------------------------------------------------------------- R2.4
C="$T/r24"; H="$C/home"
mkdir -p "$H/.claude"
printf '{"skillUsage": {not json' >"$H/.claude.json"
run_inv "$C" "$H"
check r2_4_missing_or_malformed_sources_warn "$C" '
assert d["plugins"] == [], "plugins %r, want []" % d["plugins"]
lines = err.splitlines()
assert any(l.startswith("warning: source missing") and "installed_plugins.json" in l for l in lines), \
    "no stderr warning: source missing naming installed_plugins.json; stderr: %r" % err
assert any(l.startswith("warning: unexpected shape") and ".claude.json" in l for l in lines), \
    "no stderr warning: unexpected shape naming .claude.json; stderr: %r" % err
w = d["warnings"]
assert isinstance(w, list), "warnings is not a list"
assert any("source missing" in x and "installed_plugins.json" in x for x in w), \
    "JSON warnings lacks source missing for installed_plugins.json: %r" % w
assert any("unexpected shape" in x and ".claude.json" in x for x in w), \
    "JSON warnings lacks unexpected shape for .claude.json: %r" % w
'

# ---------------------------------------------------------------- R2.10
C="$T/r210"; H="$C/home"
mkdir -p "$H/.claude/plugins"
echo '{"version": 2, "plugins": {}}' >"$H/.claude/plugins/installed_plugins.json"
echo '{}' >"$H/.claude/settings.json"
mkskill "$H/.claude/skills/fresh-skill" fresh-skill
mkskill "$H/.claude/skills/old-skill" old-skill
AS_OF=1760000000000
DAY=86400000
cat >"$H/.claude.json" <<EOF
{"skillUsage": {
  "fresh-skill": {"usageCount": 5, "lastUsedAt": $((AS_OF - 10 * DAY))},
  "old-skill":   {"usageCount": 5, "lastUsedAt": $((AS_OF - 100 * DAY))}
}}
EOF
run_inv "$C" "$H" --as-of-ms "$AS_OF" --dead-days 90
check r2_10_dead_and_used_30d_follow_as_of_and_dead_days "$C" '
s = d["summary"]
assert s["used_last_30d"] == 1, "used_last_30d %r, want 1" % s["used_last_30d"]
assert s["dead_count"] == 1, "dead_count %r, want 1" % s["dead_count"]
by_name = {x["name"]: x for x in d["skills"]}
for n in ("fresh-skill", "old-skill"):
    assert n in by_name, "skills lacks %s: %r" % (n, sorted(by_name))
assert by_name["old-skill"]["dead"] is True, "old-skill dead %r" % by_name["old-skill"]["dead"]
dead = sorted(x["name"] for x in d["skills"] if x.get("dead") is True)
assert dead == ["old-skill"], "skills with dead: true: %r, want [old-skill]" % dead
'

# ---------------------------------------------------------------- R2.11
C="$T/r211"; H="$C/home"
mkdir -p "$H/.claude" "$T/proj"
ln -s "$T/proj" "$T/link"
echo '{"skillUsage": {}}' >"$H/.claude.json"
run_inv "$C" "$H" --project-root "$T/link" --as-of-ms 1000 --dead-days 45
check r2_11_inventory_echoes_effective_arguments "$C" '
want = {"project_root": os.path.realpath(sys.argv[2]), "as_of_ms": 1000, "dead_days": 45}
assert d["params"] == want, "params %r, want %r" % (d["params"], want)
' "$T/proj"

if [ "$FAILS" -gt 0 ]; then
  echo "tt2_inventory_sources: $FAILS case(s) failed"
  exit 1
fi
echo "tt2_inventory_sources: all cases passed"
