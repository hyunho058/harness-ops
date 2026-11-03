"""Find the project root for check-harness (spec D12, D2).

Usage: python3 project_root.py [DIR]      (DIR defaults to the cwd)

1. If DIR is inside a git work tree, the root is ``git rev-parse
   --show-toplevel``, unless that toplevel is ``$HOME`` or an ancestor of it
   (a dotfiles repo is not a project).
2. Otherwise walk up from DIR for a directory holding ``.claude/`` or
   ``CLAUDE.md``; ``$HOME`` and every ancestor of ``$HOME`` never qualify
   (``~/.claude`` always exists, so without this every folder is a project).

Found: print the resolved path on stdout, exit 0.
Not found: print nothing on stdout, ``no project root: <reason>`` on stderr,
exit 3. Usage error (unknown flag, extra argument, DIR not a directory):
exit 2. Reads only; writes nothing.
"""

import os
import subprocess
import sys

sys.dont_write_bytecode = True  # D2: scripts never write files (no __pycache__ in the repo)

import harness_common as hc

USAGE = "usage: project_root.py [DIR]"


def usage_error(msg):
    print("project_root.py: " + msg, file=sys.stderr)
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def parse_args(argv):
    """Return the start directory from ``argv`` (D2: bad usage exits 2)."""
    if argv and argv[0] in ("-h", "--help"):
        print(USAGE)
        sys.exit(0)
    if argv and argv[0] == "--":
        argv = argv[1:]
    elif argv and argv[0].startswith("-") and argv[0] != "-":
        usage_error("unknown option: " + argv[0])
    if len(argv) > 1:
        usage_error("expected at most one DIR, got %d arguments" % len(argv))
    start = argv[0] if argv else os.getcwd()
    if not os.path.isdir(start):
        usage_error("not a directory: " + start)
    return hc.resolve(start)


def excluded_dirs():
    """Return the resolved ``$HOME`` and all of its ancestors (never a project)."""
    cur = hc.resolve(hc.home())
    out = {cur}
    while True:
        parent = os.path.dirname(cur)
        if parent == cur:
            return out
        out.add(parent)
        cur = parent


def git_toplevel(start, notes):
    """Return the resolved git toplevel of ``start``, or ``None``.

    "Not a git repository" is the normal non-git case and stays silent; a
    missing ``git`` or any other failure is recorded in ``notes`` as a D2
    ``git unavailable`` warning. ``GIT_DIR``/``GIT_WORK_TREE`` from the
    caller's environment are dropped so they cannot redirect the lookup.
    """
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE")}
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=start, env=env, capture_output=True, text=True, check=False,
        )
    except FileNotFoundError:
        notes.append("git unavailable: git not found")
        return None
    except OSError as exc:
        notes.append("git unavailable: %s" % exc)
        return None
    if proc.returncode != 0:
        detail = (proc.stderr.strip().splitlines() or [""])[0]
        lowered = detail.lower()
        if "not a git repository" not in lowered and "must be run in a work tree" not in lowered:
            notes.append("git unavailable: git rev-parse exit %d: %s"
                         % (proc.returncode, detail or "no output"))
        return None
    top = proc.stdout.strip()
    return hc.resolve(top) if top else None


def walk_up(start, excluded):
    """Return the nearest dir at or above ``start`` with ``.claude/`` or ``CLAUDE.md``."""
    cur = start
    while True:
        if cur not in excluded and (
            os.path.isdir(os.path.join(cur, ".claude"))
            or os.path.isfile(os.path.join(cur, "CLAUDE.md"))
        ):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent


def main(argv):
    start = parse_args(argv)
    excluded = excluded_dirs()
    home = hc.resolve(hc.home())
    notes = []

    top = git_toplevel(start, notes)
    if top is not None and top not in excluded:
        print(top)
        return 0

    root = walk_up(start, excluded)
    if root is not None:
        for note in notes:
            hc.warn(note)
        print(root)
        return 0

    if top is not None:
        git_part = "git toplevel %s is $HOME or an ancestor of it" % top
    else:
        git_part = "%s is not in a git work tree" % start
    print("no project root: %s, and no .claude/ or CLAUDE.md at or above it "
          "outside $HOME (%s) and its ancestors" % (git_part, home), file=sys.stderr)
    # After the reason line, so stderr still starts with "no project root:".
    for note in notes:
        hc.warn(note)
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
