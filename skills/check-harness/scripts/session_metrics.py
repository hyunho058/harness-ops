"""Compute check-harness's session metrics from Claude Code transcripts (spec D9).

Usage::

    python3 session_metrics.py [--long-session-min 20] --files-from LIST|-

``LIST`` is a newline-separated file of transcript paths, or ``-`` for stdin,
so ``session_files.py ... | session_metrics.py --files-from -`` works. Blank
lines and lines starting with ``#`` are not input; a ``# params {json}`` line
(from ``session_files.py --with-params``) is parsed and echoed as
``params.session_files``. A listed path that is missing or unreadable is
skipped with ``warning: unreadable session file: <path>``.

Each transcript is read line by line. Only tool_use metadata, top-level
timestamps, message ids and, in user messages, a match-only extraction of
``<command-name>/NAME</command-name>`` are used: no other text of a user
message is kept or emitted. Prints one JSON object (see D9 for every
definition). Ratios are rounded to 2 decimals and are ``null`` when their
denominator is 0. This script writes no files.
"""

import argparse
import collections
import datetime
import json
import math
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import harness_common as hc  # noqa: E402

AGENT_TOOLS = ("Agent", "Task")
WRITE_TOOLS = ("Write", "Edit", "MultiEdit")

PLAN_ROLES = (
    "harness-ops:specify",
    "harness-ops:scaffold",
    "harness-ops:requirements-interview",
    "harness-ops:decompose",
    "harness-ops:crew",
    "harness-ops:team-design",
    "harness-factory:design",
    "harness-factory:team-design",
)
COMPLETION_ROLES = (
    "harness-ops:loop",
    "harness-ops:qa",
    "harness-ops:build-order",
    "harness-ops:autopilot",
)
HANDOFF_SKILL_PARTS = frozenset(("session-wrap", "wrap", "compound", "remember", "handoff"))
HANDOFF_BASENAMES = frozenset(("progress.md", "build_order.md", "pipeline.md", "autopilot.md", "MEMORY.md"))
LEARNING_BASENAMES = frozenset(("CLAUDE.md", "loop.md", "MEMORY.md"))
LEARNING_PATH_PARTS = ("/.claude/rules/", "/memory/", "/docs/learnings/")

TEST_COMMAND = re.compile(
    r"(^|[\s;&|(])(pytest|python3? -m pytest|go test|cargo test|(npm|pnpm|yarn)( run)? test"
    r"|make test|vitest|jest|bats|\S*(run-tests|_test)\.sh)(\s|$)"
)
# Match-only: the group is the command name; nothing else of the message is kept.
COMMAND_NAME = re.compile(r"<command-name>/([^<>\s]+)</command-name>")
TIMESTAMP = re.compile(
    r"^(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)(?:\.(\d+))?(Z|[+-]\d\d:?\d\d)?$"
)


# --- helpers -----------------------------------------------------------------

def ratio(num, den):
    """``num / den`` rounded to 2 decimals, ``None`` when ``den`` is 0."""
    if not den:
        return None
    return round(num / den, 2)


def parse_timestamp(value):
    """Return POSIX seconds for an ISO-8601 string, or ``None``."""
    if not isinstance(value, str):
        return None
    m = TIMESTAMP.match(value.strip())
    if not m:
        return None
    year, month, day, hour, minute, second, frac, tz = m.groups()
    try:
        dt = datetime.datetime(int(year), int(month), int(day), int(hour), int(minute), int(second),
                               tzinfo=datetime.timezone.utc)
    except ValueError:
        return None
    seconds = dt.timestamp() + (float("0." + frac) if frac else 0.0)
    if tz and tz != "Z":
        sign = 1 if tz[0] == "+" else -1
        digits = tz[1:].replace(":", "")
        seconds -= sign * (int(digits[:2]) * 3600 + int(digits[2:]) * 60)
    return seconds


def command_names(content):
    """Return the typed slash-command names in a user message's content.

    Match-only: the regex is applied to each text part and only its captured
    group leaves this function. No other text is stored or returned.
    """
    if isinstance(content, str):
        return COMMAND_NAME.findall(content)
    names = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text" and isinstance(block.get("text"), str):
                names.extend(COMMAND_NAME.findall(block["text"]))
    return names


def skill_part(key):
    return hc.split_key(key)[1]


def top(counter, limit=None, minimum=1):
    """Counter -> dict ordered by count desc, then key; entries below ``minimum`` dropped."""
    items = sorted(((k, v) for k, v in counter.items() if v >= minimum), key=lambda kv: (-kv[1], kv[0]))
    if limit is not None:
        items = items[:limit]
    return dict(items)


# --- one session -------------------------------------------------------------

class Session:
    """Facts collected from one transcript."""

    def __init__(self):
        self.tools = []            # tool names in file order
        self.bash = []             # (index, command) for Bash calls
        self.write_paths = []      # file_path of Write/Edit/MultiEdit
        self.skills = []           # normalised Skill keys
        self.commands = []         # normalised typed-command keys
        self.agent_types = []
        self.agent_msgs = collections.Counter()  # message key -> Agent/Task tool_use count
        self.background = 0
        self.plan_mode = False
        self.first_ts = None
        self.last_ts = None

    def add_timestamp(self, value):
        t = parse_timestamp(value)
        if t is None:
            return
        self.first_ts = t if self.first_ts is None else min(self.first_ts, t)
        self.last_ts = t if self.last_ts is None else max(self.last_ts, t)

    def add_tool_use(self, block, msg_key):
        name = block.get("name")
        if not isinstance(name, str) or not name:
            return
        tool_input = block.get("input")
        if not isinstance(tool_input, dict):
            tool_input = {}
        index = len(self.tools)
        self.tools.append(name)
        if name == "Bash" and isinstance(tool_input.get("command"), str):
            self.bash.append((index, tool_input["command"]))
        elif name in WRITE_TOOLS and isinstance(tool_input.get("file_path"), str):
            self.write_paths.append(tool_input["file_path"])
        elif name == "Skill" and isinstance(tool_input.get("skill"), str) and tool_input["skill"].strip():
            self.skills.append(hc.normalise(tool_input["skill"].strip().lstrip("/")))
        elif name == "EnterPlanMode":
            self.plan_mode = True
        elif name in AGENT_TOOLS:
            sub = tool_input.get("subagent_type")
            self.agent_types.append(sub if isinstance(sub, str) and sub else "(unspecified)")
            self.agent_msgs[msg_key] += 1
            if tool_input.get("run_in_background") is True:
                self.background += 1

    @property
    def duration_min(self):
        if self.first_ts is None or self.last_ts is None:
            return 0.0
        return (self.last_ts - self.first_ts) / 60.0

    def invoked(self):
        return self.skills + self.commands


def read_session(path):
    """Parse one transcript line by line; ``None`` when it cannot be read."""
    session = Session()
    bad = 0
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    bad += 1
                    continue
                if not isinstance(record, dict):
                    continue
                session.add_timestamp(record.get("timestamp"))
                message = record.get("message")
                if not isinstance(message, dict):
                    continue
                kind = record.get("type")
                if kind == "assistant":
                    content = message.get("content")
                    if not isinstance(content, list):
                        continue
                    msg_id = message.get("id")
                    msg_key = msg_id if isinstance(msg_id, str) and msg_id else "line:%d" % lineno
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "tool_use":
                            session.add_tool_use(block, msg_key)
                elif kind == "user":
                    for name in command_names(message.get("content")):
                        session.commands.append(hc.normalise(name))
    except OSError:
        hc.warn("unreadable session file: " + path)
        return None
    if bad:
        hc.warn("skipped %d unparseable line(s) in %s" % (bad, path))
    return session


# --- per-session judgements (D9) ----------------------------------------------

def plans_first(s):
    return s.plan_mode or any(hc.role_match(k, PLAN_ROLES) for k in s.invoked())


def hands_off(s):
    for path in s.write_paths:
        if os.path.basename(path) in HANDOFF_BASENAMES or "/memory/" in path:
            return True
    return any(skill_part(k) in HANDOFF_SKILL_PARTS for k in s.invoked())


def checks_completion(s):
    start = math.floor(0.7 * len(s.tools))
    if any(i >= start and TEST_COMMAND.search(cmd) for i, cmd in s.bash):
        return True
    return any(hc.role_match(k, COMPLETION_ROLES) for k in s.invoked())


def writes_learning(s):
    for path in s.write_paths:
        if os.path.basename(path) in LEARNING_BASENAMES:
            return True
        if any(part in path for part in LEARNING_PATH_PARTS):
            return True
    return False


# --- input list ---------------------------------------------------------------

def read_list(source):
    """Return ``(paths, session_files_params)`` from ``--files-from``."""
    try:
        if source == "-":
            lines = sys.stdin.read().splitlines()
        else:
            with open(source, encoding="utf-8", errors="replace") as fh:
                lines = fh.read().splitlines()
    except OSError:
        hc.warn("source missing: " + hc.resolve(source))
        return [], None
    paths, params = [], None
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            if params is None and stripped.startswith("# params "):
                try:
                    value = json.loads(stripped[len("# params "):])
                except ValueError:
                    value = None
                if isinstance(value, dict):
                    params = value
                else:
                    hc.warn("unexpected shape: params line in " + ("stdin" if source == "-" else hc.resolve(source)))
            continue
        paths.append(stripped)
    return paths, params


def minutes(value):
    try:
        number = float(value)
    except ValueError:
        raise argparse.ArgumentTypeError("not a number: %r" % value)
    if number < 0 or math.isnan(number) or math.isinf(number):
        raise argparse.ArgumentTypeError("must be >= 0: %r" % value)
    return int(number) if number.is_integer() else number


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="session_metrics.py",
        description="Compute session metrics from Claude Code transcripts (D9).",
    )
    parser.add_argument("--long-session-min", type=minutes, default=20)
    parser.add_argument("--files-from", required=True)
    return parser.parse_args(argv)


# --- main ----------------------------------------------------------------------

def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    paths, session_params = read_list(args.files_from)

    tool_counts = collections.Counter()
    skills = collections.Counter()
    commands = collections.Counter()
    agents = collections.Counter()
    bash_heads = collections.Counter()
    edit_targets = collections.Counter()
    grams = collections.Counter()

    analyzed = 0
    durations = []
    long_sessions = plan_first = delegated = parallel = background = 0
    handoff = completion = learning = 0

    for path in paths:
        if not os.path.isfile(path):
            hc.warn("unreadable session file: " + path)
            continue
        s = read_session(path)
        if s is None:
            continue
        analyzed += 1
        tool_counts.update(s.tools)
        skills.update(s.skills)
        commands.update(s.commands)
        agents.update(s.agent_types)
        for _, cmd in s.bash:
            head = cmd.split("|", 1)[0].strip()
            if head:
                bash_heads[head] += 1
        edit_targets.update(s.write_paths)
        grams.update("→".join(s.tools[i:i + 3]) for i in range(len(s.tools) - 2))

        duration = s.duration_min
        durations.append(duration)
        is_long = duration >= args.long_session_min
        long_sessions += is_long
        plan_first += plans_first(s)
        delegated += bool(s.agent_types)
        parallel += sum(1 for n in s.agent_msgs.values() if n >= 2)
        background += s.background
        if is_long:
            handoff += hands_off(s)
        completion += checks_completion(s)
        learning += writes_learning(s)

    top_grams = sorted(grams.items(), key=lambda kv: (-kv[1], kv[0]))[:5]
    total_grams = sum(grams.values())

    hc.emit({
        "params": {"session_files": session_params, "long_session_min": args.long_session_min},
        "sessions_analyzed": analyzed,
        "total_tool_calls": sum(tool_counts.values()),
        "tool_frequency": top(tool_counts, 20),
        "skills_invoked": top(skills),
        "commands_invoked": top(commands),
        "agents_invoked": top(agents),
        "long_sessions": long_sessions,
        "avg_session_duration_min": round(sum(durations) / len(durations), 2) if durations else None,
        "repeated_bash_commands": top(bash_heads, 15, minimum=5),
        "repeated_edit_targets": top(edit_targets, minimum=5),
        "automation_opportunities": [{"pattern": p, "count": c} for p, c in top_grams],
        "metrics": {
            "plan_first_ratio": ratio(plan_first, analyzed),
            "delegation_ratio": ratio(delegated, analyzed),
            "parallel_count": parallel,
            "background_flag_count": background,
            "handoff_ratio": ratio(handoff, long_sessions),
            "completion_check_ratio": ratio(completion, analyzed),
            "learning_write_sessions": learning,
            "top_3gram_share": ratio(sum(c for _, c in top_grams), total_grams),
        },
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
