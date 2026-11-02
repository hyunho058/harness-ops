"""List the Claude Code session transcripts check-harness analyses (spec D7, D8).

Usage::

    python3 session_files.py --scope overall|project [--project-dir P]
                             [--days 30] [--with-params]

Prints the selected transcripts, one resolved absolute path per line, sorted.
Only top-level transcripts count: ``~/.claude/projects/<dir>/*.jsonl`` at
depth 1 inside each project dir; ``<session>/subagents/*.jsonl`` never does.
A file is selected when its mtime is within ``--days`` days (default 30).

``--scope overall`` takes every project dir. ``--scope project`` requires
``--project-dir`` (absent: exit 2) and takes the dir encoded from that path
exactly, plus the dir of every path ``git worktree list --porcelain`` reports
for it. Any other dir whose name starts with the project's encoded name is
excluded with ``warning: excluded prefix-matching session dir <name>``. When
git is missing or fails, project scope is the exact dir only, with
``warning: git unavailable: <reason>``.

``--with-params`` prints a first line ``# params {json}`` holding the
effective arguments (``scope``, resolved ``project_dir`` or ``null`` for
overall scope, ``days``); ``session_metrics.py`` skips it as input and echoes
it. Warnings go to stderr. This script writes no files.
"""

import argparse
import json
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import harness_common as hc  # noqa: E402


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="session_files.py",
        description="List top-level Claude Code session transcripts (D7).",
    )
    parser.add_argument("--scope", required=True, choices=("overall", "project"))
    parser.add_argument("--project-dir")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--with-params", action="store_true")
    args = parser.parse_args(argv)
    if args.scope == "project" and not args.project_dir:
        parser.error("--project-dir is required with --scope project")
    if args.days < 0:
        parser.error("--days must be >= 0")
    return args


def project_dirs(root):
    """Return the names of the project dirs under ``root``, sorted."""
    try:
        entries = list(os.scandir(root))
    except FileNotFoundError:
        hc.warn("source missing: " + hc.resolve(root))
        return []
    except OSError as exc:
        hc.warn("unexpected shape: %s (%s)" % (hc.resolve(root), exc.strerror or exc))
        return []
    return sorted(e.name for e in entries if e.is_dir())


def worktree_paths(project_dir):
    """Return the resolved paths ``git worktree list --porcelain`` reports, or ``None``."""
    if not os.path.isdir(project_dir):
        hc.warn("git unavailable: project dir does not exist: " + project_dir)
        return None
    out = hc.git(["worktree", "list", "--porcelain"], cwd=project_dir)
    if out is None:
        return None
    paths = []
    for line in out.splitlines():
        if line.startswith("worktree "):
            paths.append(hc.resolve(line[len("worktree "):]))
    return paths


def selected_dirs(args, names):
    """Return the project-dir names in scope."""
    if args.scope == "overall":
        return list(names)
    own = hc.encode_project_dir(args.project_dir)
    wanted = {own}
    for path in worktree_paths(args.project_dir) or []:
        wanted.add(hc.encode_project_dir(path))
    for name in names:
        if name.startswith(own) and name not in wanted:
            hc.warn("excluded prefix-matching session dir " + name)
    return [n for n in names if n in wanted]


def transcripts(dir_path, cutoff):
    """Yield resolved paths of depth-1 ``*.jsonl`` files in ``dir_path`` newer than ``cutoff``."""
    try:
        entries = list(os.scandir(dir_path))
    except OSError as exc:
        hc.warn("unexpected shape: %s (%s)" % (hc.resolve(dir_path), exc.strerror or exc))
        return
    for entry in entries:
        if not entry.name.endswith(".jsonl"):
            continue
        try:
            if not entry.is_file() or entry.stat().st_mtime < cutoff:
                continue
        except OSError:
            continue
        yield hc.resolve(entry.path)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.scope == "project":
        args.project_dir = hc.resolve(args.project_dir)
    else:
        args.project_dir = None

    if args.with_params:
        params = {"scope": args.scope, "project_dir": args.project_dir, "days": args.days}
        print("# params " + json.dumps(params, ensure_ascii=False))

    root = os.path.join(hc.home(), ".claude", "projects")
    cutoff = time.time() - args.days * 86400
    found = set()
    for name in selected_dirs(args, project_dirs(root)):
        found.update(transcripts(os.path.join(root, name), cutoff))
    for path in sorted(found):
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
