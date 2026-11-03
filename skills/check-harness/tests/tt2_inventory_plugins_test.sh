#!/usr/bin/env bash
# TT2 — acceptance tests for R2.1, R2.2, R2.3, R2.9 (portfolio inventory: plugins,
# installPath-only skill scan, MCP sources, plugin source tree; spec D5, D6, D2).
# Black box: drives skills/check-harness/scripts/inventory.py through its CLI only,
# with HOME pointed at a fixture directory.
# Run from the repo root: bash skills/check-harness/tests/tt2_inventory_plugins_test.sh
set -u

cd "$(dirname "$0")/../../.." || exit 1
export PYTHONDONTWRITEBYTECODE=1
INV="skills/check-harness/scripts/inventory.py"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
T="$(cd "$SCRATCH" && pwd -P)"   # resolved spelling of the scratch dir

FAILS=0

mkskill() { # DIR NAME
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: Fixture skill %s.\n---\n\nBody.\n' "$2" "$2" >"$1/SKILL.md"
}

# run_inv CASE_DIR HOME ARGS... — runs inventory.py, stores stdout/stderr/exit in CASE_DIR.
run_inv() {
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
assert isinstance(d, dict), "stdout is not a JSON object"
'

# check NAME CASE_DIR PYCODE [ARGS...] — PYCODE asserts on d/out/err; extra args in sys.argv[2:].
check() {
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

# ---------------------------------------------------------------- R2.1 / R2.2 fixture
C="$T/r21"; H="$C/home"; ROOT="$C/proj"
mkdir -p "$H/.claude/plugins" "$ROOT/.claude"
A_PATH="$H/.claude/plugins/cache/mkt/alpha/1.0.0"
B_PATH="$H/.claude/plugins/cache/mkt/beta/2.0.0"
mkdir -p "$A_PATH" "$B_PATH"
mkskill "$A_PATH/skills/a1" a1
mkskill "$H/.claude/plugins/cache/mkt/alpha/0.9.0/skills/a1" a1
cat >"$H/.claude/plugins/installed_plugins.json" <<EOF
{"version": 2, "plugins": {
  "alpha@mkt": [{"scope": "user", "installPath": "$A_PATH", "version": "1.0.0"}],
  "beta@mkt":  [{"scope": "user", "installPath": "$B_PATH", "version": "2.0.0"}]
}}
EOF
echo '{"enabledPlugins": {"alpha@mkt": true}}' >"$H/.claude/settings.json"
echo '{"enabledPlugins": {"beta@mkt": true}}' >"$ROOT/.claude/settings.json"
echo '{"skillUsage": {}}' >"$H/.claude.json"
run_inv "$C" "$H" --project-root "$ROOT"

check r2_1_plugins_from_installed_plugins_and_settings "$C" '
a_path = os.path.realpath(sys.argv[2])
plugins = d["plugins"]
assert isinstance(plugins, list), "plugins is not a list"
by_id = {p["id"]: p for p in plugins}
assert set(by_id) == {"alpha@mkt", "beta@mkt"}, "plugin ids: %r" % sorted(by_id)
for p in plugins:
    missing = {"id", "name", "marketplace", "version", "scope", "install_path",
               "enabled_user", "enabled_project", "skills_count"} - set(p)
    assert not missing, "plugin %s lacks %r" % (p.get("id"), sorted(missing))
a, b = by_id["alpha@mkt"], by_id["beta@mkt"]
assert a["name"] == "alpha" and a["marketplace"] == "mkt", "alpha name/marketplace: %r" % a
assert a["version"] == "1.0.0", "alpha version %r" % a["version"]
assert os.path.realpath(a["install_path"]) == a_path, "alpha install_path %r" % a["install_path"]
assert b["version"] == "2.0.0", "beta version %r" % b["version"]
assert b["install_path"], "beta install_path empty"
assert a["enabled_user"] is True, "alpha enabled_user %r" % a["enabled_user"]
assert b["enabled_project"] is True, "beta enabled_project %r" % b["enabled_project"]
assert a["enabled_project"] is False, "alpha enabled_project %r" % a["enabled_project"]
assert b["enabled_user"] is False, "beta enabled_user %r" % b["enabled_user"]
s = d["summary"]
assert s["plugins_installed"] == 2, "plugins_installed %r" % s["plugins_installed"]
assert s["plugins_enabled_user"] == 1, "plugins_enabled_user %r" % s["plugins_enabled_user"]
assert s["plugins_enabled_project"] == 1, "plugins_enabled_project %r" % s["plugins_enabled_project"]
' "$A_PATH"

check r2_2_only_install_path_is_scanned "$C" '
hits = [s for s in d["skills"] if s.get("key") == "alpha:a1"]
assert len(hits) == 1, "want exactly one alpha:a1 entry, got %d: %r" % (len(hits), hits)
p = hits[0]["path"]
assert "/1.0.0/" in p, "alpha:a1 path not under 1.0.0/: %r" % p
'

# ---------------------------------------------------------------- R2.3 fixture
C="$T/r23"; H="$C/home"; ROOT="$C/proj"; LINK="$C/link"
mkdir -p "$H/.claude/plugins" "$ROOT"
ln -s "$ROOT" "$LINK"
A_PATH="$H/.claude/plugins/cache/mkt/alpha/1.0.0"
mkdir -p "$A_PATH"
cat >"$H/.claude/plugins/installed_plugins.json" <<EOF
{"version": 2, "plugins": {
  "alpha@mkt": [{"scope": "user", "installPath": "$A_PATH", "version": "1.0.0"}]
}}
EOF
echo '{"enabledPlugins": {"alpha@mkt": true}}' >"$H/.claude/settings.json"
SRV='"command": "npx", "args": ["--token", "s3cr3t-value"], "env": {"TOKEN": "s3cr3t-value"}'
cat >"$H/.claude.json" <<EOF
{"skillUsage": {},
 "mcpServers": {"user-srv": {$SRV}},
 "projects": {"$LINK": {"mcpServers": {"local-srv": {"type": "stdio", $SRV}}}}}
EOF
echo "{\"mcpServers\": {\"project-srv\": {$SRV}}}" >"$ROOT/.mcp.json"
echo "{\"mcpServers\": {\"plugin-srv\": {$SRV}}}" >"$A_PATH/.mcp.json"
run_inv "$C" "$H" --project-root "$ROOT"

check r2_3_mcp_servers_every_source_scoped_no_secrets "$C" '
srv = d["mcp_servers"]
assert isinstance(srv, list), "mcp_servers is not a list"
for e in srv:
    missing = {"name", "scope", "source", "type"} - set(e)
    assert not missing, "mcp entry %r lacks %r" % (e.get("name"), sorted(missing))
got = {e["name"]: e["scope"] for e in srv}
want = {"user-srv": "user", "local-srv": "local", "project-srv": "project", "plugin-srv": "plugin"}
assert got == want, "mcp name->scope: %r, want %r" % (got, want)
assert len(srv) == 4, "want 4 mcp_servers entries, got %d" % len(srv)
assert d["summary"]["mcp_servers_total"] == 4, "mcp_servers_total %r" % d["summary"]["mcp_servers_total"]
assert "s3cr3t-value" not in out, "secret value appears in stdout"
'

# ---------------------------------------------------------------- R2.9 fixture
C="$T/r29"; H="$C/home"; ROOT="$C/proj"
mkdir -p "$H/.claude/plugins" "$ROOT/.claude-plugin"
echo '{"name": "alpha", "version": "1.1.0"}' >"$ROOT/.claude-plugin/plugin.json"
mkskill "$ROOT/skills/a1" a1
A_PATH="$H/.claude/plugins/cache/mkt/alpha/1.0.0"
mkskill "$A_PATH/skills/a1" a1
cat >"$H/.claude/plugins/installed_plugins.json" <<EOF
{"version": 2, "plugins": {
  "alpha@mkt": [{"scope": "user", "installPath": "$A_PATH", "version": "1.0.0"}]
}}
EOF
echo '{"enabledPlugins": {"alpha@mkt": true}}' >"$H/.claude/settings.json"
echo '{"skillUsage": {"a1": {"usageCount": 2, "lastUsedAt": 1760000000000}}}' >"$H/.claude.json"
run_inv "$C" "$H" --project-root "$ROOT"

check r2_9_source_tree_counted_once_and_stale_install_reported "$C" '
root = os.path.realpath(sys.argv[2])
hits = [s for s in d["skills"] if s.get("key") == "alpha:a1"]
assert len(hits) == 1, "want exactly one alpha:a1 entry, got %d: %r" % (len(hits), hits)
e = hits[0]
assert e["source"] == "project_local", "alpha:a1 source %r" % e["source"]
assert os.path.realpath(e["path"]).startswith(root + "/"), "alpha:a1 path not under project root: %r" % e["path"]
want = {"type": "installed_stale", "plugin": "alpha", "installed_version": "1.0.0", "source_version": "1.1.0"}
f = d["plugin_findings"]
assert any(all(x.get(k) == v for k, v in want.items()) for x in f), "plugin_findings lacks %r: %r" % (want, f)
names = [x.get("name") for x in d["usage"]["prefix_duplicates"]]
assert "a1" in names, "usage.prefix_duplicates does not list a1: %r" % d["usage"]["prefix_duplicates"]
' "$ROOT"

if [ "$FAILS" -gt 0 ]; then
  echo "tt2_inventory_plugins: $FAILS case(s) failed"
  exit 1
fi
echo "tt2_inventory_plugins: all cases passed"
