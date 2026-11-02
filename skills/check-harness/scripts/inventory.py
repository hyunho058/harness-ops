"""Portfolio inventory for check-harness (spec D4, D5, D6; CLI contract D2).

    python3 inventory.py [--project-root P] [--as-of-ms N] [--dead-days 90]

Prints one JSON object with keys ``params``, ``summary``, ``plugins``,
``mcp_servers``, ``skills``, ``usage``, ``plugin_findings`` and ``warnings``.

Sources (all read-only):

* Installed plugins: ``~/.claude/plugins/installed_plugins.json``; skills are
  scanned only under each entry's ``installPath`` (never every cached version).
* Enabled plugins: ``~/.claude/settings.json`` (user) and
  ``<root>/.claude/settings.json`` + ``settings.local.json`` (project).
* MCP servers: ``~/.claude.json`` ``mcpServers`` (user),
  ``~/.claude.json`` ``projects[<key>].mcpServers`` whose resolved key is the
  resolved project root (local), ``<root>/.mcp.json`` (project), and each
  enabled plugin's ``installPath/.mcp.json`` and
  ``installPath/.claude-plugin/plugin.json`` ``mcpServers`` (plugin). Only
  name, scope, source file and type are emitted -- never ``env``,
  ``headers``, ``args`` or URLs.
* Skills: ``~/.claude/skills/*/SKILL.md`` (user_standalone), each installed
  plugin's ``installPath/skills/*/SKILL.md`` (plugin), and
  ``<root>/skills/*/SKILL.md`` + ``<root>/.claude/skills/**/SKILL.md``
  (project_local). Plugin commands count as skills: each installed plugin's
  ``installPath/commands/*.md`` and, in a plugin source tree,
  ``<root>/commands/*.md`` (name = basename without ``.md``). When ``<root>/.claude-plugin/plugin.json`` exists, the
  project's ``skills/*`` take that plugin's name as owner and the installed
  copy of the same plugin is not scanned (D6).
* Usage: ``~/.claude.json`` ``skillUsage``, classified per D4.

Without ``--project-root`` no project source is read (never the cwd).
Nothing is written; warnings go to stderr and into ``warnings`` (D2).
"""

import argparse
import os
import sys

sys.dont_write_bytecode = True  # D2: scripts never write files (no __pycache__ in the repo)
import time

import harness_common as hc

DAY_MS = 86400000
WINDOW_DAYS = 30  # D8: one 30-day window everywhere


# --- arguments ---------------------------------------------------------------

def parse_args(argv):
    parser = argparse.ArgumentParser(prog="inventory.py", description=__doc__.splitlines()[0])
    parser.add_argument("--project-root", default=None)
    parser.add_argument("--as-of-ms", type=int, default=None)
    parser.add_argument("--dead-days", type=int, default=90)
    args = parser.parse_args(argv)  # unknown flag or bad value -> exit 2 (D2)
    if args.dead_days < 0:
        parser.error("--dead-days must be >= 0")
    if args.as_of_ms is None:
        args.as_of_ms = int(time.time() * 1000)
    if args.project_root is not None:
        args.project_root = hc.resolve(args.project_root)
        if not os.path.isdir(args.project_root):
            hc.warn("source missing: " + args.project_root)
    return args


# --- skills ------------------------------------------------------------------

def skill_dirs(parent):
    """``(dir_name, resolved SKILL.md)`` for every ``parent/*/SKILL.md``, sorted."""
    if not os.path.isdir(parent):
        return []
    found = []
    for name in sorted(os.listdir(parent)):
        path = os.path.join(parent, name, "SKILL.md")
        if os.path.isfile(path):
            found.append((name, hc.resolve(path)))
    return found


def command_files(parent):
    """``(basename without .md, resolved file)`` for every ``parent/*.md``, sorted.

    Plugin commands are skills for D5's purpose: Claude Code records
    ``<plugin>:<command>`` invocations in ``skillUsage``.
    """
    if not os.path.isdir(parent):
        return []
    found = []
    for name in sorted(os.listdir(parent)):
        path = os.path.join(parent, name)
        if name.endswith(".md") and len(name) > 3 and os.path.isfile(path):
            found.append((name[:-3], hc.resolve(path)))
    return found


def plugin_entries(base):
    """``skills/*/SKILL.md`` plus ``commands/*.md`` under a plugin root (D5)."""
    return skill_dirs(os.path.join(base, "skills")) + command_files(os.path.join(base, "commands"))


def skill_tree(parent):
    """``(dir_name, resolved SKILL.md)`` for every ``parent/**/SKILL.md``, sorted.

    Follows directory symlinks, visiting each resolved directory once so a
    link cycle cannot loop.
    """
    if not os.path.isdir(parent):
        return []
    found, seen = [], set()
    for dirpath, dirnames, filenames in os.walk(parent, followlinks=True):
        real = hc.resolve(dirpath)
        if real in seen:
            dirnames[:] = []
            continue
        seen.add(real)
        dirnames.sort()
        if "SKILL.md" in filenames and hc.resolve(dirpath) != hc.resolve(parent):
            found.append((os.path.basename(dirpath), hc.resolve(os.path.join(dirpath, "SKILL.md"))))
    return sorted(found, key=lambda x: x[1])


def make_skill(name, owner, source, path):
    raw = owner + ":" + name if owner else name
    return {
        "name": name,
        "key": hc.normalise(raw),
        "owner": owner,
        "source": source,
        "path": path,
        "usage_count": 0,
        "last_used_at": None,
        "dead": False,
    }


# --- MCP servers ---------------------------------------------------------------

def server_type(config):
    if isinstance(config, dict):
        if isinstance(config.get("type"), str):
            return config["type"]
        if "command" in config:
            return "stdio"
    return None


def servers_from(mapping, scope, source):
    """Safe ``{name, scope, source, type}`` entries; config values are never copied."""
    return [
        {"name": name, "scope": scope, "source": source, "type": server_type(cfg)}
        for name, cfg in sorted(mapping.items())
    ]


def file_servers(path, scope, optional):
    """Servers from a ``.mcp.json``-shaped file's ``mcpServers`` key.

    ``optional``: a missing file is normal (most projects and plugins have
    none) and stays silent; a malformed file or key still warns.
    """
    data = hc.load_json(path, missing_ok=optional)
    if data is None:
        return []
    value = hc.get_key(data, "mcpServers", dict, path)
    return servers_from(value or {}, scope, hc.resolve(path))


def plugin_manifest_servers(install_path):
    """Servers from ``installPath/.claude-plugin/plugin.json`` ``mcpServers``.

    The key may be an inline map or a path (relative to the plugin root) to a
    ``.mcp.json``-shaped file; absent is normal and silent.
    """
    manifest = os.path.join(install_path, ".claude-plugin", "plugin.json")
    data = hc.load_json(manifest, missing_ok=True)
    if data is None or "mcpServers" not in data:
        return []
    value = data["mcpServers"]
    if isinstance(value, dict):
        return servers_from(value, "plugin", hc.resolve(manifest))
    if isinstance(value, str):
        return file_servers(os.path.join(install_path, value), "plugin", optional=False)
    hc.warn("unexpected shape: " + hc.resolve(manifest) + ".mcpServers")
    return []


# --- usage -------------------------------------------------------------------

def usage_records(claude):
    """``{raw_key: (usage_count, last_used_at)}`` from ``skillUsage``."""
    data, path = claude
    if data is None:
        return {}
    value = hc.get_key(data, "skillUsage", dict, path)
    records = {}
    for key, rec in sorted((value or {}).items()):
        if not isinstance(rec, dict):
            hc.warn("unexpected shape: %s.skillUsage.%s" % (hc.resolve(path), key))
            continue
        count = rec.get("usageCount", 0)
        last = rec.get("lastUsedAt")
        if not isinstance(count, int) or isinstance(count, bool):
            hc.warn("unexpected shape: %s.skillUsage.%s.usageCount" % (hc.resolve(path), key))
            count = 0
        if last is not None and (not isinstance(last, (int, float)) or isinstance(last, bool)):
            hc.warn("unexpected shape: %s.skillUsage.%s.lastUsedAt" % (hc.resolve(path), key))
            last = None
        records[key] = (count, int(last) if last is not None else None)
    return records


def merge_usage(skill, count, last):
    skill["usage_count"] += count
    if last is not None and (skill["last_used_at"] is None or last > skill["last_used_at"]):
        skill["last_used_at"] = last


def classify(skills, records):
    """Apply D4 to every ``skillUsage`` key; merge usage into ``skills`` in place."""
    by_key = {}
    for s in skills:
        by_key.setdefault(s["key"], []).append(s)
    unowned_names = {s["name"] for s in skills if s["owner"] is None}
    owned_by_name = {}
    for s in skills:
        if s["owner"] is not None:
            owned_by_name.setdefault(hc.split_key(s["key"])[1], set()).add(s["key"])

    renamed, builtin, ghost = [], [], []
    builtin_keys = set()
    dup_keys = {}  # bare name -> (owned skill key, set of raw keys)

    for raw, (count, last) in sorted(records.items()):
        key = hc.normalise(raw)
        owner, bare = hc.split_key(key)
        if key in by_key:                                   # (1) installed
            for s in by_key[key]:
                merge_usage(s, count, last)
            if raw != key:
                renamed.append({"from": raw, "to": key})
        elif hc.is_builtin(key):                            # (2) builtin
            builtin.append(raw)
            builtin_keys.add(key)
        elif (owner is None and bare not in unowned_names   # (3) prefix_duplicate
              and len(owned_by_name.get(bare, ())) == 1):
            skill_key = next(iter(owned_by_name[bare]))
            # The same skill recorded twice: its bare record counts toward it.
            for s in by_key[skill_key]:
                merge_usage(s, count, last)
            dup_keys.setdefault(bare, (skill_key, set()))[1].add(raw)
        else:                                               # (4) ghost
            ghost.append({"key": raw, "usage_count": count, "last_used_at": last})

    prefix_duplicates = []
    for bare, (skill_key, raws) in sorted(dup_keys.items()):
        raws |= {r for r in records if hc.normalise(r) == skill_key}
        prefix_duplicates.append({"name": bare, "skill_key": skill_key, "keys": sorted(raws)})

    by_bare = {}
    for key in set(by_key) | builtin_keys:
        by_bare.setdefault(hc.split_key(key)[1], set()).add(key)
    name_collisions = [
        {"name": bare, "keys": sorted(keys)}
        for bare, keys in sorted(by_bare.items())
        if len(keys) >= 2
    ]

    return {
        "renamed": renamed,
        "builtin": builtin,
        "prefix_duplicates": prefix_duplicates,
        "ghost": ghost,
        "name_collisions": name_collisions,
    }


# --- main --------------------------------------------------------------------

def main(argv):
    args = parse_args(argv)
    root = args.project_root
    home = hc.home()

    claude_path = os.path.join(home, ".claude.json")
    claude = (hc.load_json(claude_path), claude_path)

    # Plugins (D5) and the project's own plugin source tree (D6).
    installed = hc.installed_plugins()
    enabled = hc.enabled_plugins(root)
    source = hc.plugin_source(root)

    skills, findings, plugins = [], [], []
    seen_paths = set()

    def add(skill):
        if skill["path"] in seen_paths:
            return
        seen_paths.add(skill["path"])
        skills.append(skill)

    # Project sources first, so a SKILL.md reached twice keeps its owned entry.
    if root:
        owner = source["name"] if source else None
        for name, path in skill_dirs(os.path.join(root, "skills")):
            add(make_skill(name, owner, "project_local", path))
        if source:
            for name, path in command_files(os.path.join(root, "commands")):
                add(make_skill(name, owner, "project_local", path))
        for name, path in skill_tree(os.path.join(root, ".claude", "skills")):
            add(make_skill(name, None, "project_local", path))

    for name, path in skill_dirs(os.path.join(home, ".claude", "skills")):
        add(make_skill(name, None, "user_standalone", path))

    stale_reported = set()
    for p in installed:
        found = plugin_entries(p["install_path"])
        superseded = source is not None and source["name"] == p["name"]
        if superseded:
            if (p["id"] not in stale_reported and isinstance(p["version"], str)
                    and isinstance(source["version"], str) and p["version"] != source["version"]):
                stale_reported.add(p["id"])
                findings.append({
                    "type": "installed_stale",
                    "plugin": p["name"],
                    "installed_version": p["version"],
                    "source_version": source["version"],
                })
        else:
            for name, path in found:
                add(make_skill(name, p["name"], "plugin", path))
        plugins.append({
            "id": p["id"],
            "name": p["name"],
            "marketplace": p["marketplace"],
            "version": p["version"],
            "scope": p["scope"],
            "install_path": p["install_path"],
            "enabled_user": p["id"] in enabled["user"],
            "enabled_project": p["id"] in enabled["project"],
            "skills_count": len(found),
        })

    # MCP servers (D5): user, local, project, plugin.
    mcp = []
    data = claude[0]
    if data is not None:
        # Optional keys: Claude Code omits them when nothing is configured, so
        # an absent key is empty without a warning; a wrong type still warns.
        mcp += servers_from(hc.get_key(data, "mcpServers", dict, claude_path, missing_ok=True) or {},
                            "user", hc.resolve(claude_path))
        if root:
            projects = hc.get_key(data, "projects", dict, claude_path, missing_ok=True) or {}
            for pkey, entry in sorted(projects.items()):
                if hc.resolve(pkey) != root or not isinstance(entry, dict):
                    continue
                value = entry.get("mcpServers")
                if value is None:
                    continue
                if not isinstance(value, dict):
                    hc.warn("unexpected shape: %s.projects.%s.mcpServers" % (hc.resolve(claude_path), pkey))
                    continue
                mcp += servers_from(value, "local", hc.resolve(claude_path))
    if root:
        mcp += file_servers(os.path.join(root, ".mcp.json"), "project", optional=True)
    done = set()
    for p in plugins:
        if not (p["enabled_user"] or p["enabled_project"]) or p["install_path"] in done:
            continue
        done.add(p["install_path"])
        mcp += file_servers(os.path.join(p["install_path"], ".mcp.json"), "plugin", optional=True)
        mcp += plugin_manifest_servers(p["install_path"])

    # Usage (D4) and the dead / 30-day flags (D5, D8).
    skills.sort(key=lambda s: (s["key"], s["path"]))
    usage = classify(skills, usage_records(claude))
    dead_cutoff = args.as_of_ms - args.dead_days * DAY_MS
    window_cutoff = args.as_of_ms - WINDOW_DAYS * DAY_MS
    used_30d = 0
    for s in skills:
        last = s["last_used_at"]
        s["dead"] = s["usage_count"] == 0 or (last is not None and last < dead_cutoff)
        if last is not None and window_cutoff <= last <= args.as_of_ms:
            used_30d += 1

    installed_ids = {p["id"] for p in plugins}
    summary = {
        "total_installed": len(skills),
        "used_last_30d": used_30d,
        "dead_count": sum(1 for s in skills if s["dead"]),
        "ghost_count": len(usage["ghost"]),
        "renamed_count": len(usage["renamed"]),
        "prefix_duplicates": len(usage["prefix_duplicates"]),
        "name_collisions": len(usage["name_collisions"]),
        "plugins_installed": len(installed_ids),
        "plugins_enabled_user": len(installed_ids & set(enabled["user"])),
        "plugins_enabled_project": len(installed_ids & set(enabled["project"])),
        "mcp_servers_total": len(mcp),
    }

    hc.emit({
        "params": {"project_root": root, "as_of_ms": args.as_of_ms, "dead_days": args.dead_days},
        "summary": summary,
        "plugins": plugins,
        "mcp_servers": mcp,
        "skills": skills,
        "usage": usage,
        "plugin_findings": findings,
        "warnings": [],
    })
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
