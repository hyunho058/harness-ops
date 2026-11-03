#!/usr/bin/env bash
# TT2 — acceptance tests for R2.5, R2.6, R2.7, R2.8 (classification of skillUsage
# keys: renamed, builtin, prefix_duplicates, ghost, name_collisions; spec D4, D5, D2).
# Black box: drives skills/check-harness/scripts/inventory.py through its CLI only,
# with HOME pointed at a fixture directory.
# Run from the repo root: bash skills/check-harness/tests/tt2_inventory_usage_test.sh
set -u

cd "$(dirname "$0")/../../.." || exit 1
export PYTHONDONTWRITEBYTECODE=1
INV="skills/check-harness/scripts/inventory.py"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
T="$(cd "$SCRATCH" && pwd -P)"

FAILS=0
TS=1760000000000   # lastUsedAt, epoch ms

mkskill() { # DIR NAME
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: Fixture skill %s.\n---\n\nBody.\n' "$2" "$2" >"$1/SKILL.md"
}

# new_home CASE_DIR PLUGIN_ID|- SKILL... — fixture HOME with one installed plugin
# (or none for "-") holding the given skills; sets H.
new_home() {
  local c="$1" id="$2"
  shift 2
  H="$c/home"
  mkdir -p "$H/.claude/plugins"
  echo '{}' >"$H/.claude/settings.json"
  if [ "$id" = "-" ]; then
    echo '{"version": 2, "plugins": {}}' >"$H/.claude/plugins/installed_plugins.json"
    return
  fi
  local name="${id%@*}" mkt="${id#*@}"
  local ip="$H/.claude/plugins/cache/$mkt/$name/1.0.0" s
  mkdir -p "$ip"
  for s in "$@"; do mkskill "$ip/skills/$s" "$s"; done
  cat >"$H/.claude/plugins/installed_plugins.json" <<EOF
{"version": 2, "plugins": {"$id": [{"scope": "user", "installPath": "$ip", "version": "1.0.0"}]}}
EOF
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
u = d["usage"]
renamed = [x["from"] for x in u["renamed"]]
builtin = list(u["builtin"])
ghost = [x["key"] for x in u["ghost"]]
dups = [x["name"] for x in u["prefix_duplicates"]]
'

check() { # NAME CASE_DIR PYCODE
  local name="$1" c="$2" code="$3"
  if [ ! -f "$INV" ]; then
    echo "FAIL - $name: $INV does not exist"; FAILS=$((FAILS + 1)); return
  fi
  if python3 -c "$PRE$code" "$c" 2>"$c/assert.err"; then
    echo "ok   - $name"
  else
    echo "FAIL - $name: $(tail -n 3 "$c/assert.err" | tr '\n' ' ')"
    FAILS=$((FAILS + 1))
  fi
}

# ---------------------------------------------------------------- R2.5
C="$T/r25"; mkdir -p "$C"
new_home "$C" harness-ops@mkt context-audit
cat >"$H/.claude.json" <<EOF
{"skillUsage": {
  "harness:doc-drift":         {"usageCount": 3, "lastUsedAt": $TS},
  "harness-ops:context-audit": {"usageCount": 2, "lastUsedAt": $TS}
}}
EOF
run_inv "$C" "$H"
check r2_5_renamed_history_merges_into_installed_skill "$C" '
hits = [s for s in d["skills"] if s.get("key") == "harness-ops:context-audit"]
assert len(hits) == 1, "want one harness-ops:context-audit skill entry, got %r" % hits
assert hits[0]["usage_count"] == 5, "usage_count %r, want 5" % hits[0]["usage_count"]
assert "harness:doc-drift" in renamed, "usage.renamed does not list harness:doc-drift: %r" % u["renamed"]
assert "harness:doc-drift" not in ghost, "usage.ghost lists harness:doc-drift"
assert d["summary"]["ghost_count"] == 0, "ghost_count %r, want 0" % d["summary"]["ghost_count"]
'

# ---------------------------------------------------------------- R2.6
C="$T/r26"; mkdir -p "$C"
new_home "$C" harness-ops@mkt loop
cat >"$H/.claude.json" <<EOF
{"skillUsage": {
  "loop":             {"usageCount": 4, "lastUsedAt": $TS},
  "harness-ops:loop": {"usageCount": 1, "lastUsedAt": $TS}
}}
EOF
run_inv "$C" "$H"
check r2_6_builtins_not_ghosts_and_same_name_skills_collide "$C" '
assert "loop" in builtin, "usage.builtin does not list loop: %r" % builtin
assert "loop" not in ghost, "usage.ghost lists loop"
assert "loop" not in dups, "usage.prefix_duplicates lists loop"
want = sorted(["loop", "harness-ops:loop"])
cols = u["name_collisions"]
assert any(sorted(x["keys"]) == want for x in cols), "no name_collisions entry with keys %r: %r" % (want, cols)
'

# ---------------------------------------------------------------- R2.7
C="$T/r27"; mkdir -p "$C"
new_home "$C" alpha@mkt report
cat >"$H/.claude.json" <<EOF
{"skillUsage": {
  "report":       {"usageCount": 2, "lastUsedAt": $TS},
  "alpha:report": {"usageCount": 3, "lastUsedAt": $TS}
}}
EOF
run_inv "$C" "$H"
check r2_7_bare_record_of_one_owned_skill_is_prefix_duplicate "$C" '
hits = [x for x in u["prefix_duplicates"] if x["name"] == "report"]
assert len(hits) == 1, "want one prefix_duplicates entry for report, got %r" % u["prefix_duplicates"]
assert sorted(hits[0]["keys"]) == ["alpha:report", "report"], "keys %r" % hits[0]["keys"]
assert d["summary"]["prefix_duplicates"] == 1, "summary.prefix_duplicates %r, want 1" % d["summary"]["prefix_duplicates"]
'

# ---------------------------------------------------------------- R2.8
C="$T/r28"; mkdir -p "$C"
new_home "$C" -
cat >"$H/.claude.json" <<EOF
{"skillUsage": {
  "vanished-skill": {"usageCount": 2, "lastUsedAt": $TS},
  "gone:thing":     {"usageCount": 1, "lastUsedAt": $TS}
}}
EOF
run_inv "$C" "$H"
check r2_8_unknown_keys_are_ghosts "$C" '
assert "vanished-skill" in ghost, "usage.ghost does not list vanished-skill: %r" % ghost
assert "gone:thing" in ghost, "usage.ghost does not list gone:thing: %r" % ghost
assert d["summary"]["ghost_count"] == 2, "ghost_count %r, want 2" % d["summary"]["ghost_count"]
'

if [ "$FAILS" -gt 0 ]; then
  echo "tt2_inventory_usage: $FAILS case(s) failed"
  exit 1
fi
echo "tt2_inventory_usage: all cases passed"
