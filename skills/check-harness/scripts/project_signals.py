"""Project signals for project-automation-auditor and context-quality-reviewer.

Usage::

    python3 project_signals.py --project-root P [--as-of-ms N]

Prints one JSON object (spec D14, D15, D18, D6) with the keys ``params``,
``plugin_source``, ``hooks``, ``planning_artifacts``, ``ledgers``,
``lessons``, ``skills``, ``agents``, ``checker_citations``, ``unattended``,
``compounding`` and ``warnings``.

* ``hooks`` lists every hook as ``{source, event, matcher, command}`` from
  ``.claude/settings.json`` (``project``), ``.claude/settings.local.json``
  (``project_local``), ``~/.claude/settings.json`` (``user``), the project's
  ``hooks/hooks.json`` when it is a plugin source tree (``plugin_source``) and
  each enabled installed plugin's ``installPath/hooks/hooks.json``
  (``plugin:<name@marketplace>``). Whether a command formats, lints or blocks
  is the auditor's judgement, not this script's.
* Ledgers (``loop.md``, ``autopilot.md``, ``build_order.md``,
  ``pipeline.md``) are searched under the root without following directory
  symlinks, skipping skill bodies, stubs, templates and fixtures; a
  ``loop.md`` or ``autopilot.md`` counts only when its structure is a real
  ledger's (D15).
* Git-derived fields are ``null`` with ``warning: git unavailable`` when git
  is missing or the root is not in a work tree (D2).
* Every path in ``lessons.files``, ``checker_citations``, ``skills[].path``,
  ``agents[].path`` and ``unattended.autopilot_files[].path`` is relative to
  the project root.

The script reads only; it writes nothing (D2). Exit 0 on success (including
degraded success with warnings), 2 on a usage error.
"""

import argparse
import os
import re
import sys

sys.dont_write_bytecode = True  # D2: scripts never write files (no __pycache__ in the repo)
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import harness_common as hc  # noqa: E402

DAY_MS = 86400 * 1000

ANALYZERS = (
    "skill-portfolio-analyzer",
    "session-pattern-analyzer",
    "context-quality-reviewer",
    "project-automation-auditor",
)
ANALYZER_OWNER = "harness-ops"

AUTOPILOT_LIMITS = (
    "wall_clock_cap_hours",
    "max_ticks",
    "consecutive_park_cap",
    "per_tick_timeout_seconds",
    "crash_loop",
    "killswitch_path",
)

LEDGER_NAMES = ("loop.md", "autopilot.md", "build_order.md", "pipeline.md")
# Directory names skipped at any depth during the ledger search.
SKIP_ANY_DEPTH = frozenset({".git", "node_modules", "tests"})
# Root-relative directories skipped during the ledger search: skill bodies,
# parity stubs, agent bodies and templates (D15).
SKIP_ROOT_REL = frozenset({".claude/skills", "skills", "agents", "references"})

LESSON_FORMS = frozenset({"gate1-command", "gate3-item", "context"})
HARDENED_LINES = frozenset({"- form: gate1-command", "- form: gate3-item"})

CITATION_RE = re.compile(r"capability:spawn-(inline|named)-checker\b")
KV_RE = re.compile(r"^\s*-\s+([A-Za-z0-9_]+)\s*:(.*)$")
PLACEHOLDER_RE = re.compile(r"<[^<>]*>")
COMMIT_MARK = "\x1ecommit "


# --- small helpers --------------------------------------------------------

def rel(root, path):
    """Return ``path`` relative to ``root`` with ``/`` separators."""
    return os.path.relpath(path, root).replace(os.sep, "/")


def read_text(path):
    """Return a file's text, or ``None`` after ``unexpected shape`` when unreadable."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        hc.warn("unexpected shape: " + hc.resolve(path))
        return None


def heading_re(title):
    """A ``## <title>`` heading, optionally followed by whitespace and text (D15)."""
    return re.compile(r"^## " + re.escape(title) + r"(\s.*)?$")


def section(lines, title):
    """Return the lines under the first ``## <title>`` heading, or ``None``.

    The section ends at the next level-1 or level-2 heading.
    """
    pat = heading_re(title)
    for i, line in enumerate(lines):
        if pat.match(line.rstrip("\n")):
            body = []
            for nxt in lines[i + 1:]:
                if re.match(r"^#{1,2}\s", nxt):
                    break
                body.append(nxt)
            return body
    return None


def parse_value(raw):
    """D15 value parsing: drop a trailing `` #…`` comment and trim."""
    cut = raw.find(" #")
    if cut != -1:
        raw = raw[:cut]
    return raw.strip()


def is_placeholder(value):
    """A value is a placeholder when empty, ``—``, or holding a ``<…>`` span."""
    return value == "" or value == "—" or bool(PLACEHOLDER_RE.search(value))


def kv_lines(lines):
    """Yield ``(key, parsed value)`` for every ``- key: value`` line."""
    for line in lines:
        m = KV_RE.match(line.rstrip("\n"))
        if m:
            yield m.group(1), parse_value(m.group(2))


def frontmatter(text):
    """Parse a leading ``---`` YAML block's top-level scalar keys (stdlib only).

    Handles ``key: value``, quoted values and ``|`` / ``>`` block scalars.
    Returns ``None`` when the text has no frontmatter.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None
    out = {}
    body = lines[1:end]
    i = 0
    while i < len(body):
        m = re.match(r"^([A-Za-z0-9_-]+)\s*:(.*)$", body[i])
        i += 1
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if val[:1] in ("|", ">"):
            block = []
            while i < len(body) and (not body[i].strip() or body[i][:1] in (" ", "\t")):
                block.append(body[i].strip())
                i += 1
            while block and not block[-1]:
                block.pop()
            val = ("\n" if val[0] == "|" else " ").join(block).strip()
        elif len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1]
        out[key] = val
    return out


def walk(top, skip_dir=None):
    """``os.walk`` that never follows directory symlinks, pruned by ``skip_dir(path)``."""
    for dirpath, dirnames, filenames in os.walk(top, followlinks=False):
        if skip_dir is not None:
            dirnames[:] = [d for d in dirnames if not skip_dir(os.path.join(dirpath, d))]
        dirnames.sort()
        yield dirpath, sorted(filenames)


def files_under(root, sub, predicate):
    """Root-relative-sorted absolute paths under ``root/sub`` whose basename passes."""
    top = os.path.join(root, sub)
    if not os.path.isdir(top):
        return []
    found = []
    for dirpath, filenames in walk(top):
        for name in filenames:
            path = os.path.join(dirpath, name)
            if predicate(name) and os.path.isfile(path):
                found.append(path)
    return found


def glob_one_level(root, parent, child):
    """Paths ``root/parent/*/child`` that are files, sorted."""
    top = os.path.join(root, parent)
    if not os.path.isdir(top):
        return []
    out = []
    for name in sorted(os.listdir(top)):
        path = os.path.join(top, name, child)
        if os.path.isfile(path):
            out.append(path)
    return out


# --- hooks (D14) ----------------------------------------------------------

def hooks_from(path, source, optional):
    """List ``{source, event, matcher, command}`` from one hooks-bearing JSON file."""
    data = hc.load_json(path, missing_ok=optional)
    if data is None:
        return []
    events = hc.get_key(data, "hooks", dict, path, missing_ok=True)
    out = []
    for event, groups in sorted((events or {}).items()):
        if not isinstance(groups, list):
            hc.warn("unexpected shape: %s.hooks.%s" % (hc.resolve(path), event))
            continue
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks", []), list):
                hc.warn("unexpected shape: %s.hooks.%s" % (hc.resolve(path), event))
                continue
            matcher = group.get("matcher")
            for hook in group.get("hooks", []):
                if not isinstance(hook, dict):
                    hc.warn("unexpected shape: %s.hooks.%s" % (hc.resolve(path), event))
                    continue
                command = hook.get("command")
                out.append({
                    "source": source,
                    "event": event,
                    "matcher": matcher if isinstance(matcher, str) else None,
                    "command": command if isinstance(command, str) else None,
                })
    return out


def collect_hooks(root, plugin):
    hooks = []
    hooks += hooks_from(os.path.join(root, ".claude", "settings.json"), "project", True)
    hooks += hooks_from(os.path.join(root, ".claude", "settings.local.json"), "project_local", True)
    hooks += hooks_from(os.path.join(hc.home(), ".claude", "settings.json"), "user", False)
    if plugin is not None:
        hooks += hooks_from(os.path.join(root, "hooks", "hooks.json"), "plugin_source", True)
    enabled = hc.enabled_plugins(root)
    wanted = set(enabled["user"]) | set(enabled["project"])
    seen = set()
    for entry in hc.installed_plugins():
        if entry["id"] not in wanted:
            continue
        marker = (entry["id"], entry["install_path"])
        if marker in seen:
            continue
        seen.add(marker)
        path = os.path.join(entry["install_path"], "hooks", "hooks.json")
        hooks += hooks_from(path, "plugin:" + entry["id"], True)
    return hooks


# --- planning artifacts (D15 B2) -------------------------------------------

def planning_artifacts(root):
    counts = {
        "spec": len(glob_one_level(root, "specs", "spec.md")),
        "partition_manifest": len(glob_one_level(root, "specs", "partition-manifest.md")),
        "design": len(glob_one_level(root, "specs", "design.md")),
        "brief": len(glob_one_level(root, "specs", "brief.md")),
        "insights": len(glob_one_level(root, "requirements-interview-outputs", "insights.md")),
    }
    counts["exist"] = any(v > 0 for v in counts.values())
    return counts


# --- ledgers (D15, D18) ----------------------------------------------------

def find_ledgers(root):
    """Map each ledger basename to its found absolute paths (sorted by root-relative path)."""

    def skip(path):
        name = os.path.basename(path)
        if name in SKIP_ANY_DEPTH:
            return True
        return rel(root, path) in SKIP_ROOT_REL

    found = {name: [] for name in LEDGER_NAMES}
    for dirpath, filenames in walk(root, skip):
        for name in filenames:
            if name in found:
                path = os.path.join(dirpath, name)
                if os.path.isfile(path):
                    found[name].append(path)
    for name in found:
        found[name].sort(key=lambda p: rel(root, p))
    return found


def is_real_loop(text):
    """A ``loop.md`` with ``## Lessons`` and ≥1 ``### `` record whose ``form`` is one value."""
    lessons = section(text.splitlines(), "Lessons")
    if lessons is None:
        return False
    in_record = False
    for line in lessons:
        if line.startswith("### "):
            in_record = True
            continue
        if in_record:
            m = KV_RE.match(line)
            if m and m.group(1) == "form" and parse_value(m.group(2)) in LESSON_FORMS:
                return True
    return False


def autopilot_status(text):
    """Return ``missing_limits`` for a real autopilot ledger, or ``None`` for a template."""
    lines = text.splitlines()
    state = section(lines, "State")
    if state is None:
        return None
    started = dict(kv_lines(state)).get("run_started_at")
    if started is None or is_placeholder(started):
        return None
    config = dict(kv_lines(section(lines, "Config") or []))
    return [k for k in AUTOPILOT_LIMITS if k not in config or is_placeholder(config[k])]


# --- skills, agents, citations (D15, D6) -----------------------------------

def make_key(owner, name):
    return hc.normalise(owner + ":" + name if owner else name)


def list_skills(root, plugin):
    owner = plugin["name"] if plugin else None
    out = []
    seen = set()
    sources = [(p, owner) for p in glob_one_level(root, "skills", "SKILL.md")]
    sources += [(p, None) for p in files_under(root, os.path.join(".claude", "skills"),
                                                lambda n: n == "SKILL.md")]
    for path, own in sources:
        real = hc.resolve(path)
        if real in seen:
            continue
        seen.add(real)
        text = read_text(path)
        if text is None:
            continue
        fm = frontmatter(text) or {}
        name = fm.get("name") or os.path.basename(os.path.dirname(path))
        out.append({"path": rel(root, path), "name": name, "key": make_key(own, name)})
    # Plugin commands are skills for D4 too (the D5 amendment): in a plugin source
    # tree, commands/*.md are invoked as <plugin>:<basename> and recorded in skillUsage.
    if plugin:
        cmd_dir = os.path.join(root, "commands")
        if os.path.isdir(cmd_dir) and not os.path.islink(cmd_dir):
            for entry in sorted(os.listdir(cmd_dir)):
                path = os.path.join(cmd_dir, entry)
                if not entry.endswith(".md") or not os.path.isfile(path):
                    continue
                real = hc.resolve(path)
                if real in seen:
                    continue
                seen.add(real)
                name = entry[:-3]
                out.append({"path": rel(root, path), "name": name, "key": make_key(owner, name)})
    return out


def list_agents(root, plugin):
    owner = plugin["name"] if plugin else None
    out = []
    seen = set()
    for sub, own in (("agents", owner), (os.path.join(".claude", "agents"), None)):
        top = os.path.join(root, sub)
        if not os.path.isdir(top):
            continue
        for name in sorted(os.listdir(top)):
            path = os.path.join(top, name)
            if (not name.endswith(".md") or name.lower() == "readme.md"
                    or not os.path.isfile(path)):
                continue
            real = hc.resolve(path)
            if real in seen:
                continue
            seen.add(real)
            text = read_text(path)
            if text is None:
                continue
            fm = frontmatter(text) or {}
            # Without frontmatter the file is still registered; name it by its stem.
            agent = fm.get("name") or name[:-3]
            key = make_key(own, agent)
            out.append({
                "path": rel(root, path),
                "name": agent,
                "key": key,
                "description": fm.get("description"),
                "analyzer": key in {ANALYZER_OWNER + ":" + a for a in ANALYZERS},
            })
    return out


def checker_citations(root):
    """Root-relative skill files citing a spawn-*-checker capability, check-harness excluded."""
    excluded = hc.resolve(os.path.join(root, "skills", "check-harness")) + os.sep
    candidates = list(glob_one_level(root, "skills", "SKILL.md"))
    skills_dir = os.path.join(root, "skills")
    if os.path.isdir(skills_dir):
        for name in sorted(os.listdir(skills_dir)):
            refs = os.path.join(skills_dir, name, "references")
            if os.path.isdir(refs):
                candidates += [os.path.join(refs, f) for f in sorted(os.listdir(refs))
                               if f.endswith(".md") and os.path.isfile(os.path.join(refs, f))]
    candidates += files_under(root, os.path.join(".claude", "skills"), lambda n: n.endswith(".md"))
    out = []
    seen = set()
    for path in candidates:
        real = hc.resolve(path)
        if real in seen or real.startswith(excluded):
            continue
        seen.add(real)
        text = read_text(path)
        if text is not None and CITATION_RE.search(text):
            out.append(rel(root, path))
    return sorted(out)


# --- git-derived fields ----------------------------------------------------

class Git:
    """Git queries for one root; every method returns ``None`` once git failed."""

    def __init__(self, root, as_of_ms):
        self.root = root
        self.as_of_s = as_of_ms // 1000
        if not os.path.isdir(root):
            hc.warn("git unavailable: project root is not a directory")
            self.ok = False
        else:
            self.ok = hc.git(["rev-parse", "--is-inside-work-tree"], root) is not None

    def _since(self, days):
        return self.as_of_s - days * 86400

    def commits(self, args, pathspecs):
        """Yield ``(commit_time, body_lines)`` for commits touching ``pathspecs``."""
        out = hc.git(["log", "--no-color", "--no-ext-diff", "--relative",
                      "--format=%x1ecommit %ct"] + args + ["--"] + pathspecs, self.root)
        if out is None:
            self.ok = False
            return None
        result = []
        for chunk in out.split(COMMIT_MARK)[1:]:
            head, _, body = chunk.partition("\n")
            try:
                ct = int(head.strip())
            except ValueError:
                continue
            result.append((ct, body.splitlines()))
        return result

    def in_window(self, ct, days):
        return self._since(days) <= ct <= self.as_of_s

    def touched_within(self, pathspecs, days):
        """True when any commit within ``days`` touches ``pathspecs``."""
        if not self.ok:
            return None
        if not pathspecs:
            return False
        commits = self.commits([], pathspecs)
        if commits is None:
            return None
        return any(self.in_window(ct, days) for ct, _ in commits)

    def files_changed(self, pathspecs, days, added_only, name_filter=None):
        """Distinct root-relative files added (or changed) within ``days``."""
        if not self.ok:
            return None
        args = ["--name-only"] + (["--diff-filter=A"] if added_only else [])
        commits = self.commits(args, pathspecs)
        if commits is None:
            return None
        names = set()
        for ct, body in commits:
            if not self.in_window(ct, days):
                continue
            for line in body:
                line = line.strip()
                if line and (name_filter is None or name_filter(line)):
                    names.add(line)
        return len(names)

    def hardened_added(self, pathspecs, days):
        """Added diff lines exactly ``- form: gate1-command|gate3-item`` within ``days``."""
        if not self.ok:
            return None
        if not pathspecs:
            return 0
        commits = self.commits(["-p", "--no-renames"], pathspecs)
        if commits is None:
            return None
        count = 0
        for ct, body in commits:
            if not self.in_window(ct, days):
                continue
            for line in body:
                if line.startswith("+") and not line.startswith("+++"):
                    if line[1:].rstrip() in HARDENED_LINES:
                        count += 1
        return count


def compounding(root, gitq):
    def under(*prefixes):
        return lambda p: any(p.startswith(x) for x in prefixes)

    learnings = os.path.join(root, "docs", "learnings")
    docs_exist = bool(files_under(root, os.path.join("docs", "learnings"), lambda n: True)) \
        if os.path.isdir(learnings) else False
    return {
        "claude_md_updated_30d": gitq.touched_within(["CLAUDE.md"], 30),
        "rules_added_90d": gitq.files_changed([".claude/rules"], 90, True),
        "skills_added_90d": gitq.files_changed(
            ["skills", ".claude/skills"], 90, True,
            lambda p: os.path.basename(p) == "SKILL.md"),
        "hooks_added_90d": gitq.files_changed(
            ["hooks", ".claude/hooks", ".claude/settings.json"], 90, False,
            under("hooks/", ".claude/hooks/", ".claude/settings.json")),
        "agents_added_90d": gitq.files_changed(
            ["agents", ".claude/agents"], 90, True,
            under("agents/", ".claude/agents/")),
        "docs_learnings_exist": docs_exist,
    }


# --- main ------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(prog="project_signals.py", description=__doc__.split("\n")[0])
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--as-of-ms", type=int, default=None)
    args = parser.parse_args(argv)

    root = hc.resolve(args.project_root)
    as_of_ms = args.as_of_ms if args.as_of_ms is not None else int(time.time() * 1000)
    if not os.path.isdir(root):
        hc.warn("source missing: " + root)

    plugin = hc.plugin_source(root)
    hooks = collect_hooks(root, plugin)

    ledgers = find_ledgers(root)
    real_loops = []
    for path in ledgers["loop.md"]:
        text = read_text(path)
        if text is not None and is_real_loop(text):
            real_loops.append(rel(root, path))

    autopilot_files = []
    for path in ledgers["autopilot.md"]:
        text = read_text(path)
        if text is None:
            continue
        missing = autopilot_status(text)
        if missing is None:
            hc.warn("template-only autopilot.md: " + rel(root, path))
            continue
        autopilot_files.append({"path": rel(root, path), "missing_limits": missing})

    gitq = Git(root, as_of_ms)
    lessons = {
        "files": real_loops,
        "updated_30d": gitq.touched_within(real_loops, 30),
        "hardened_added_90d": gitq.hardened_added(real_loops, 90),
    }

    result = {
        "params": {"project_root": root, "as_of_ms": as_of_ms},
        "plugin_source": plugin,
        "hooks": hooks,
        "planning_artifacts": planning_artifacts(root),
        "ledgers": {
            "build_order": len(ledgers["build_order.md"]),
            "pipeline": len(ledgers["pipeline.md"]),
            "autopilot": len(autopilot_files),
        },
        "lessons": lessons,
        "skills": list_skills(root, plugin),
        "agents": list_agents(root, plugin),
        "checker_citations": checker_citations(root),
        "unattended": {
            "autopilot_files": autopilot_files,
            "conforming": (all(not f["missing_limits"] for f in autopilot_files)
                           if autopilot_files else None),
        },
        "compounding": compounding(root, gitq),
        "warnings": [],
    }
    hc.emit(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
