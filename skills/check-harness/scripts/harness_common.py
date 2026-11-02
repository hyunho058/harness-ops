"""Shared helpers for check-harness's collection scripts.

Every sibling script imports this module (run as ``python3 <path>``, never
``-I``, so this directory is on ``sys.path``). It implements the spec's D2
contract:

* User files are read from ``$HOME`` (tests point ``HOME`` at a fixture).
* Results go to stdout; warnings go to stderr as ``warning: <msg>`` lines and
  are also collected so ``emit()`` can copy them into the JSON ``warnings``.
* Faults never abort: a missing source gives ``source missing: <file>``; a
  file that does not parse, or a known key with the wrong type, gives
  ``unexpected shape: <file>[.<key>]`` and that source is treated as empty;
  a failing or missing ``git`` gives ``git unavailable: <reason>``.
* Every path printed or encoded is resolved with ``os.path.realpath`` first.
* Nothing here writes a file.

Skill-name normalisation follows D3 through
``../references/skill-aliases.tsv``, the single alias table.
"""

import functools
import json
import os
import re
import subprocess
import sys

WARNINGS = []
"""Warnings collected by ``warn()`` in order, without duplicates."""

ALIASES_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "references", "skill-aliases.tsv"
)


# --- environment and warnings ---------------------------------------------

def home():
    """Return the user's home directory from ``$HOME`` (unresolved)."""
    return os.environ.get("HOME") or os.path.expanduser("~")


def warn(msg):
    """Print ``warning: msg`` to stderr and record it for ``emit()``.

    A message already recorded is not repeated, so a helper called in a loop
    (e.g. ``git``) reports one fault once.
    """
    if msg in WARNINGS:
        return
    WARNINGS.append(msg)
    print("warning: " + msg, file=sys.stderr)


def resolve(path):
    """Return ``os.path.realpath(path)`` (``/tmp`` and ``/private/tmp`` agree)."""
    return os.path.realpath(path)


def encode_project_dir(path):
    """Return Claude Code's project-dir name for ``path`` (D7).

    The path is resolved, then every character outside ``[A-Za-z0-9]``
    becomes ``-`` (``/private/tmp/x`` -> ``-private-tmp-x``).
    """
    return re.sub(r"[^A-Za-z0-9]", "-", resolve(path))


# --- JSON sources ------------------------------------------------------------

def load_json(path, expect=dict, missing_ok=False):
    """Load a JSON file whose top level should be of type ``expect``.

    Returns the parsed value, or ``None`` after a D2 warning:
    ``source missing: <file>`` when the file does not exist (silent when
    ``missing_ok``), ``unexpected shape: <file>`` when it is unreadable, does
    not parse, or its top level is not ``expect``.
    """
    shown = resolve(path)
    if not os.path.exists(path):
        if not missing_ok:
            warn("source missing: " + shown)
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        warn("unexpected shape: " + shown)
        return None
    if expect is not None and not isinstance(data, expect):
        warn("unexpected shape: " + shown)
        return None
    return data


def get_key(data, key, expect, path, missing_ok=False):
    """Return ``data[key]`` when it has type ``expect``, else ``None``.

    A missing key warns ``source missing: <file>.<key>`` (silent when
    ``missing_ok``); a value of the wrong type warns
    ``unexpected shape: <file>.<key>``. ``path`` names the source file.
    """
    shown = resolve(path) + "." + key
    if not isinstance(data, dict) or key not in data:
        if not missing_ok:
            warn("source missing: " + shown)
        return None
    value = data[key]
    if not isinstance(value, expect):
        warn("unexpected shape: " + shown)
        return None
    return value


# --- skill names (D3) ------------------------------------------------------

@functools.lru_cache(maxsize=None)
def load_aliases():
    """Read the alias table next to this script (D3), cached.

    Returns ``{"prefix": {from: to}, "rename": {from: to}, "builtin":
    frozenset, "builtin_namespace": frozenset}``. A missing table warns
    ``source missing``; a malformed row warns ``unexpected shape`` and is
    skipped.
    """
    tables = {"prefix": {}, "rename": {}, "builtin": set(), "builtin_namespace": set()}
    shown = resolve(ALIASES_FILE)
    try:
        with open(ALIASES_FILE, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        warn("source missing: " + shown)
        lines = []
    for n, line in enumerate(lines, 1):
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if cols == ["kind", "from", "to"]:
            continue
        if len(cols) != 3 or not cols[1]:
            warn("unexpected shape: %s:%d" % (shown, n))
            continue
        kind, src, dst = cols
        if kind in ("prefix", "rename"):
            tables[kind][src] = dst
        elif kind in ("builtin", "builtin-namespace"):
            tables[kind.replace("-", "_")].add(src)
        else:
            warn("unexpected shape: %s:%d" % (shown, n))
    tables["builtin"] = frozenset(tables["builtin"])
    tables["builtin_namespace"] = frozenset(tables["builtin_namespace"])
    return tables


def split_key(key):
    """Split a name at the first ``:`` into ``(owner, skill)``; owner may be ``None``."""
    if ":" in key:
        owner, skill = key.split(":", 1)
        return owner, skill
    return None, key


def normalise(name):
    """Return the D3 key for a recorded skill name.

    Split at the first ``:``, map the owner through ``prefix`` rows, form
    ``owner:skill`` (bare ``skill`` when there was no owner), then replace the
    whole key through a ``rename`` row whose ``from`` equals it. Owners are
    kept, so built-in ``loop`` and ``harness-ops:loop`` stay distinct.
    """
    aliases = load_aliases()
    owner, skill = split_key(name.strip())
    if owner is None:
        key = skill
    else:
        key = aliases["prefix"].get(owner, owner) + ":" + skill
    return aliases["rename"].get(key, key)


def is_builtin(key):
    """True when ``key`` is a bare ``builtin`` name or its owner is a ``builtin-namespace``."""
    aliases = load_aliases()
    owner, skill = split_key(key)
    if owner is None:
        return skill in aliases["builtin"]
    return owner in aliases["builtin_namespace"]


def role_match(key, full_keys):
    """True when ``key`` matches the role list ``full_keys`` (D3 Role match).

    A key matches when it equals a listed key, or when it is bare, is not a
    built-in, and equals the skill part of a listed key (a user's standalone
    ``specify`` counts for ``harness-ops:specify``; built-in ``loop`` never
    counts for ``harness-ops:loop``). A built-in matches only when the list
    names it bare. Both sides are normalised first.
    """
    key = normalise(key)
    listed = {normalise(k) for k in full_keys}
    if key in listed:
        return True
    owner, skill = split_key(key)
    if owner is not None or is_builtin(key):
        return False
    return any(split_key(k)[1] == skill for k in listed)


# --- plugins (D5, D6) ------------------------------------------------------

def installed_plugins():
    """List installed plugins from ``~/.claude/plugins/installed_plugins.json``.

    The file's ``plugins`` map is ``name@marketplace`` -> list of
    ``{scope, installPath, version}``. Returns one dict per entry:
    ``{id, name, marketplace, scope, install_path, version}`` with
    ``install_path`` resolved. Bad entries warn ``unexpected shape`` and are
    skipped; a missing file or key warns and yields ``[]``.
    """
    path = os.path.join(home(), ".claude", "plugins", "installed_plugins.json")
    data = load_json(path)
    plugins = get_key(data, "plugins", dict, path) if data is not None else None
    result = []
    for pid, entries in sorted((plugins or {}).items()):
        if not isinstance(entries, list):
            warn("unexpected shape: %s.plugins.%s" % (resolve(path), pid))
            continue
        name, _, marketplace = pid.partition("@")
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("installPath"), str):
                warn("unexpected shape: %s.plugins.%s" % (resolve(path), pid))
                continue
            result.append({
                "id": pid,
                "name": name,
                "marketplace": marketplace,
                "scope": entry.get("scope"),
                "install_path": resolve(entry["installPath"]),
                "version": entry.get("version"),
            })
    return result


def _enabled_from(path, optional=False):
    """Return ``{plugin_id: bool}`` from one settings file's ``enabledPlugins``.

    ``optional`` (project settings files): a missing file or key is normal and
    stays silent; a malformed file or a wrong-typed key still warns.
    """
    data = load_json(path, missing_ok=optional)
    if data is None:
        return {}
    value = get_key(data, "enabledPlugins", dict, path, missing_ok=optional)
    return {k: v for k, v in (value or {}).items() if isinstance(v, bool)}


def enabled_plugins(project_root=None):
    """Return ``{"user": [ids], "project": [ids]}`` of enabled plugin ids (D5).

    User = ``~/.claude/settings.json`` ``enabledPlugins``; project =
    ``<root>/.claude/settings.json`` then ``settings.local.json`` (the local
    file overrides), read only when ``project_root`` is given. Ids whose value
    is ``true`` are listed, sorted.
    """
    user = _enabled_from(os.path.join(home(), ".claude", "settings.json"))
    project = {}
    if project_root:
        for name in ("settings.json", "settings.local.json"):
            project.update(_enabled_from(os.path.join(project_root, ".claude", name), optional=True))
    return {
        "user": sorted(k for k, v in user.items() if v),
        "project": sorted(k for k, v in project.items() if v),
    }


def plugin_source(project_root):
    """Return ``{name, version, path}`` from ``<root>/.claude-plugin/plugin.json`` (D6).

    ``None`` when the file is absent (not a plugin source tree; no warning)
    or when it has no string ``name`` (warns ``unexpected shape``).
    """
    if not project_root:
        return None
    path = os.path.join(project_root, ".claude-plugin", "plugin.json")
    data = load_json(path, missing_ok=True)
    if data is None:
        return None
    name = data.get("name")
    if not isinstance(name, str) or not name:
        warn("unexpected shape: " + resolve(path) + ".name")
        return None
    version = data.get("version")
    return {
        "name": name,
        "version": version if isinstance(version, str) else None,
        "path": resolve(path),
    }


# --- git and output --------------------------------------------------------

def git(args, cwd):
    """Run ``git <args>`` in ``cwd`` and return stdout, or ``None``.

    On a missing ``git`` binary or a non-zero exit, warns
    ``git unavailable: <reason>`` and returns ``None``; callers then set
    every git-derived field to ``null`` (D2).
    """
    try:
        proc = subprocess.run(
            ["git"] + list(args), cwd=cwd, capture_output=True, text=True, check=False
        )
    except FileNotFoundError:
        warn("git unavailable: git not found")
        return None
    except OSError as exc:
        warn("git unavailable: %s" % exc)
        return None
    if proc.returncode != 0:
        detail = (proc.stderr.strip().splitlines() or ["no output"])[0]
        warn("git unavailable: git %s exit %d: %s" % (args[0] if args else "", proc.returncode, detail))
        return None
    return proc.stdout


def emit(obj):
    """Print ``obj`` as JSON (indent 2, UTF-8 kept) with collected warnings merged.

    Warnings already in ``obj["warnings"]`` come first, then those recorded by
    ``warn()``, without duplicates.
    """
    merged = list(obj.get("warnings") or [])
    merged += [w for w in WARNINGS if w not in merged]
    obj["warnings"] = merged
    print(json.dumps(obj, indent=2, ensure_ascii=False))
