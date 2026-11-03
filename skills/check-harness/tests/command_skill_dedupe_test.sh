#!/usr/bin/env bash
# A plugin's commands/x.md beside its skills/x/SKILL.md is one skill under one
# skillUsage key, so inventory.py and project_signals.py must list it once.
# Found on a real run: harness-factory ships generate-team both ways, and the
# duplicate inflated total_installed and dead_count by one each.
# Black box: drives both scripts through their CLIs, with HOME pointed at a fixture.
# Run from the repo root: bash skills/check-harness/tests/command_skill_dedupe_test.sh
set -u

cd "$(dirname "$0")/../../.." || exit 1
export PYTHONDONTWRITEBYTECODE=1
INV="skills/check-harness/scripts/inventory.py"
SIG="skills/check-harness/scripts/project_signals.py"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
T="$(cd "$SCRATCH" && pwd -P)"
FAILS=0

mkskill() { # DIR NAME
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: Fixture skill %s.\n---\n\nBody.\n' "$2" "$2" >"$1/SKILL.md"
}
mkcmd() { # DIR NAME
  mkdir -p "$1"
  printf -- '---\ndescription: Fixture command %s.\n---\n\nBody.\n' "$2" >"$1/$2.md"
}

# check NAME JSONFILE PYCODE — PYCODE asserts on d (the parsed JSON).
check() {
  local name="$1" f="$2" code="$3"
  if python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
$code" "$f" 2>"$f.assert"; then
    echo "ok   - $name"
  else
    echo "FAIL - $name: $(tail -n 3 "$f.assert" | tr '\n' ' ')"
    FAILS=$((FAILS + 1))
  fi
}

AS_OF=1793666846016

# --- installed plugin: skills/gen + commands/gen, plus a command-only build ---
H="$T/home"
P="$H/.claude/plugins/cache/mkt/fac/1.0.0"
mkskill "$P/skills/gen" gen
mkcmd "$P/commands" gen
mkcmd "$P/commands" build
mkdir -p "$H/.claude/plugins"
cat >"$H/.claude/plugins/installed_plugins.json" <<EOF
{"version": 2, "plugins": {"fac@mkt": [{"scope": "user", "installPath": "$P", "version": "1.0.0"}]}}
EOF
echo '{"enabledPlugins": {"fac@mkt": true}}' >"$H/.claude/settings.json"
echo '{"skillUsage": {"fac:gen": {"usageCount": 3, "lastUsedAt": 1700000000000}}}' >"$H/.claude.json"

HOME="$H" python3 "$INV" --as-of-ms "$AS_OF" >"$T/inv.json" 2>"$T/inv.err"
check "installed plugin: command beside SKILL.md is listed once, as the SKILL.md" "$T/inv.json" '
gen = [s for s in d["skills"] if s["key"] == "fac:gen"]
assert len(gen) == 1, "fac:gen listed %d times: %r" % (len(gen), [s["path"] for s in gen])
assert gen[0]["path"].endswith("/skills/gen/SKILL.md"), "kept %r, not the SKILL.md" % gen[0]["path"]
assert gen[0]["usage_count"] == 3, "usage not merged into the kept entry: %r" % gen[0]'
check "installed plugin: a command with no SKILL.md is still a skill" "$T/inv.json" '
assert [s["key"] for s in d["skills"] if s["key"] == "fac:build"] == ["fac:build"], [s["key"] for s in d["skills"]]'
check "installed plugin: totals count each key once" "$T/inv.json" '
assert d["summary"]["total_installed"] == 2, d["summary"]
assert d["summary"]["dead_count"] == 2, d["summary"]
fac = [p for p in d["plugins"] if p["name"] == "fac"][0]
assert fac["skills_count"] == 2, "skills_count %r" % fac["skills_count"]'

# --- plugin source tree: the same pair under the project root ---
ROOT="$T/proj"
mkdir -p "$ROOT/.claude-plugin"
echo '{"name": "src", "version": "0.1.0"}' >"$ROOT/.claude-plugin/plugin.json"
mkskill "$ROOT/skills/gen" gen
mkcmd "$ROOT/commands" gen
mkcmd "$ROOT/commands" only
H2="$T/home2"; mkdir -p "$H2/.claude"

HOME="$H2" python3 "$INV" --project-root "$ROOT" --as-of-ms "$AS_OF" >"$T/inv2.json" 2>"$T/inv2.err"
check "source tree (inventory): command beside SKILL.md is listed once" "$T/inv2.json" '
keys = sorted(s["key"] for s in d["skills"])
assert keys == ["src:gen", "src:only"], keys'

( cd "$ROOT" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
HOME="$H2" python3 "$SIG" --project-root "$ROOT" --as-of-ms "$AS_OF" >"$T/sig.json" 2>"$T/sig.err"
check "source tree (project_signals): command beside SKILL.md is listed once" "$T/sig.json" '
keys = sorted(s["key"] for s in d["skills"])
assert keys == ["src:gen", "src:only"], keys
gen = [s for s in d["skills"] if s["key"] == "src:gen"][0]
assert gen["path"].endswith("skills/gen/SKILL.md"), gen'

if [ "$FAILS" -gt 0 ]; then
  echo "command_skill_dedupe: $FAILS case(s) failed"
  exit 1
fi
echo "command_skill_dedupe: all cases passed"
