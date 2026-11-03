#!/usr/bin/env python3
"""Print the normalised skill key for each recorded skill name (spec D3, R1).

Usage: python3 skill_name.py NAME...

For every argument, in order, prints one line ``NAME<TAB>KEY`` where KEY is
``harness_common.normalise(NAME)`` (owner mapped through the ``prefix`` rows of
``../references/skill-aliases.tsv``, then the whole key through ``rename``).
No arguments, or an argument that looks like a flag, is a usage error: exit 2
with empty stdout (D2).
"""

import os
import sys

sys.dont_write_bytecode = True  # D2: scripts never write files (no __pycache__)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import harness_common  # noqa: E402

USAGE = "usage: skill_name.py NAME..."


def main(argv):
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    for name in argv:
        if name.startswith("-"):
            print("unknown flag: %s\n%s" % (name, USAGE), file=sys.stderr)
            return 2
    for name in argv:
        print("%s\t%s" % (name, harness_common.normalise(name)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
