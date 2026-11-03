---
name: check-harness
argument-hint: ""
description: |
  Harness maturity diagnosis — evaluates the harness cycle (Scaffolding → Context → Planning →
  Execution → Verification → Compounding) using a **6-axis 26-item checklist** and a
  **2×3 analysis matrix** (Static/Behavioral/Growth × User/Project).
  All judgments stem from the gap between "what is set up (Static) ↔ what is actually done (Behavioral)"
  or "whether the harness is growing (Growth)".
  Runs 4 subagents in parallel (skill-portfolio-analyzer, session-pattern-analyzer,
  context-quality-reviewer, project-automation-auditor).
  session-pattern-analyzer is run twice — once for User global scope and once for the current
  project — to separate User/Project scopes.

  Use whenever the user asks to audit their Claude Code harness, review skill
  portfolio health, evaluate execution patterns across sessions, check project
  context/rules quality, or wants to know what's missing in their AI setup —
  even if they don't say "check-harness" explicitly.

  Trigger: "/check-harness", "check harness", "harness check", "harness audit",
  "settings check", "what's missing", "harness diagnosis",
  "maturity check", "my claude setup", "skill cleanup".
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Agent
  - AskUserQuestion
---

# /check-harness — Harness Maturity Diagnosis (v3)

> **Runtime contract — read this first.** Before executing any step below, read
> `../../references/runtime-tools.md`. This skill names **capabilities**, not runtime tool
> names. The four analyzers are spawned with the pinned `capability:spawn-named-checker`
> procedure — a divergent procedure, so each analyzer's spawn return is required evidence and,
> under Antigravity, the subagent registry is read and recorded as well (see "Delegation
> assertion" in Phase 1). A report file that exists proves nothing on its own: an agent that
> skipped delegation and wrote it in-context produces an identical file.

Evaluates along the **6-axis cycle**: **Scaffolding → Context → Planning → Execution → Verification → Compounding**.
Checklist source: `references/checklist.md` (must read first to confirm item definitions).

**Definition of analysis**
> Measure the **gap** between what is set up (Static) and what is actually done (Behavioral), across the User/Project scopes.
> Axis 6 (Compounding) is the only time-axis — it checks whether learning flows back into artifacts and accumulates (Growth).

**2 deliverables**
1. **Scorecard** — PASS/WEAK_PASS/FAIL/N/A per axis + User/Project maturity levels
2. **Action report** — TL;DR + cycle narrative + Quick Wins

**Output format** — Rich per-axis render in conversation + HTML/MD file save + auto-open
- **Conversation**: 6 × per-axis sections + inline ASCII score bars + checklist tables (Phase 3 A block)
- **Files**: saved to this run's own `REPORT_DIR` (Phase 0 › Report directory),
  `.harness/check-reports/check-harness-{YYYY-MM-DD}-{HHMMSS}-{scope}-{runtime}/`
  - `report.html` — visual report (CSS score gauge, per-axis expandable panels, self-contained)
  - `report.md` — markdown mirror (for diff·git·archive)
- **Auto-open**: `capability:run-command` → `open {dir}/report.html` at the end
- End of report one-liner: `📁 Saved: {dir}/ · 🌐 Opened: report.html`
- `{dir}` is `REPORT_DIR` everywhere in this file.

---

## Phase 0 — Scope Decision

If scope is explicit in user input, use it as-is:
- `overall` / `user` → User only
- `project` → Project only
- `all` / unspecified → **Both**

If scope is ambiguous, ask with `capability:ask-user`:

```
question: "How far should we diagnose?"
options:
  - Both (User + Project) — Full diagnosis (Recommended)
  - User only (global · skill cleanup + all session habits)
  - Project only (current project context·automation·project sessions)
```

Then run the five setup steps below, in order, before any spawn. The first four record a value
that Phase 1 passes to the analyzers and the Delegation assertion checks against; the fifth
reserves the folder Phase 3 writes the report into.

**`run-command` is required from here on.** Every step below and every analyzer's scripts run
through `capability:run-command`. If it is refused or does not exist at any step of Phase 0, halt
with `denied: run-command requires permission not granted (Phase 0: <step>)` or
`unavailable: run-command not provided by <runtime> (Phase 0: <step>)` (the map's `## Halting`
rows) and print no score. Do not continue: without it every script-owned item turns N/A, and a
report that looks complete but measured nothing misrepresents itself.

### Harness root

`ROOT` = `capability:resolve-harness-root`. Validate it with the canonical test before using it,
via `capability:run-command`:

```bash
test -d "{ROOT}/skills" && test -d "{ROOT}/agents" && test -f "{ROOT}/skills/check-harness/scripts/project_root.py"
```

A non-zero exit halts the run with `unresolved: harness root did not validate at {ROOT}`. Never
guess another root and never reason about what a script would have printed.

### Run time

Record `AS_OF_MS` (the current epoch time in milliseconds) once, via `capability:run-command`:

```bash
python3 -c 'import time; print(int(time.time() * 1000))'
```

Every analyzer that takes a reference time gets this one value, so every `--as-of-ms` in the run
is one check-harness chose and can compare with the script's `params`.

### Project root

Run `project_root.py` from the session's working directory (the user's project) via
`capability:run-command`:

```bash
python3 "{ROOT}/skills/check-harness/scripts/project_root.py"
```

| Result | `PROJECT_ROOT` | Project scope |
|---|---|---|
| exit 0 | the single line on stdout (already a resolved absolute path) | on, if selected |
| exit 3 | none | **off** — the report states the stderr reason (`no project root: …`) |
| any other non-zero exit | none | **off** — the report states `warning: script failed: project_root.py exit <n>` |

A failed discovery is never a halt: User scope still runs, and PORTFOLIO is spawned without a
`project_root`. If the user asked for Project only and discovery fails, there is nothing left to
score — say why and stop. A `run-command` refusal here is not a failed discovery: it halts per the
rule above, with `<step>` = `project_root.py`.

### Cache directory

Each run gets its own directory, so two concurrent runs, or runs in two worktrees, never
overwrite each other's analyzer files. One `capability:run-command` call (a shell variable does not
survive between calls):

```bash
mkdir -p "${TMPDIR:-/tmp}/cc-cache/check-harness" \
  && d=$(mktemp -d "${TMPDIR:-/tmp}/cc-cache/check-harness/run.XXXXXX") \
  && mkdir "$d/scratch-PORTFOLIO" "$d/scratch-SESSION_USER" "$d/scratch-SESSION_PROJECT" \
           "$d/scratch-CONTEXT" "$d/scratch-AUTOMATION" \
  && printf '%s\n' "$d"
```

Record the printed path as `CACHE_DIR`. All five `scratch-<NAME>` directories are created
whatever the scope. Paths in this run:

| Path | Written by |
|---|---|
| `{CACHE_DIR}/<NAME>.json` — `PORTFOLIO`, `SESSION_USER`, `SESSION_PROJECT`, `CONTEXT`, `AUTOMATION` | check-harness, from each analyzer's return (`capability:write-file`) |
| `{CACHE_DIR}/scratch-<NAME>/<script>.json` (`session_files.txt` for `session_files.py`) | that analyzer only — its scripts' stdout |

The report footer prints `CACHE_DIR`.

### Report directory

Each run also writes its report to a folder of its own. A name made of the date and scope alone
let a Claude Code run and an agy run on the same project and day write the same
`report.html` and `report.md`, so the later run silently replaced the earlier one's report.
The name adds the run's local time (from `AS_OF_MS`, to the second) and the runtime — the column
id from `../../references/runtime-tools.md` › How to use this file, `claude-code` or `agy` —
and a run that still finds its name taken takes the next free `-2`, `-3`, … suffix. One
`capability:run-command` call, from the session's working directory, with `{scope}` = `user`,
`project` or `all`:

```bash
python3 - "{AS_OF_MS}" "{scope}" "{runtime}" <<'EOF'
import os, sys, time
ms, scope, runtime = sys.argv[1:]
stamp = time.strftime("%Y-%m-%d-%H%M%S", time.localtime(int(ms) / 1000))
base = os.path.join(".harness", "check-reports", "check-harness-%s-%s-%s" % (stamp, scope, runtime))
os.makedirs(os.path.dirname(base), exist_ok=True)
path, n = base, 1
while True:
    try:
        os.mkdir(path)
        break
    except FileExistsError:
        n += 1
        path = "%s-%d" % (base, n)
print(os.path.realpath(path))
EOF
```

Record the printed path as `REPORT_DIR`. `mkdir` without `-p` is what makes the folder this run's:
it fails when the name exists, so two runs can never share one. Phase 3 writes `report.md` and
`report.html` only into `REPORT_DIR`, and never into an existing report folder.

---

## Phase 1 — Parallel Data Collection

**Spawn all subagents for the selected scope in a single message.**

Every prompt passes `harness_root={ROOT}`, `cache_dir={CACHE_DIR}`, `days=30` and its report name
(`report=<NAME>`). The analyzers run their scripts with these values and echo them back in each
script's `params`, which the Delegation assertion compares with what this prompt said. Each
analyzer's final message is its report JSON only; it writes scratch files only under
`{cache_dir}/scratch-<NAME>/` and saves no report itself.

### User scope agents (2)

```
capability:spawn-named-checker
  checker: "skill-portfolio-analyzer",
  description: "Skill portfolio health scan",
  prompt: """
    report=PORTFOLIO
    harness_root={ROOT}
    cache_dir={CACHE_DIR}
    project_root={PROJECT_ROOT}   (omit this line when there is no PROJECT_ROOT)
    as_of_ms={AS_OF_MS}
    days=30, dead_days=90
    Inventory installed skills, plugins and MCP servers with inventory.py; judge
    description-duplicate clusters and trigger collisions; estimate MCP usage over the
    last 30 days from top-level session files.
    Return the PORTFOLIO JSON as your final message.
  """
)

capability:spawn-named-checker
  checker: "session-pattern-analyzer",
  description: "User-wide session pattern scan",
  prompt: """
    report=SESSION_USER
    harness_root={ROOT}
    cache_dir={CACHE_DIR}
    scope=overall, days=30, long_session_min=20
    tool_use metadata only, from session_files.py + session_metrics.py. Never read prompt text.
    Return the SESSION_USER JSON as your final message.
  """
)
```

### Project scope agents (3)

```
capability:spawn-named-checker
  checker: "session-pattern-analyzer",
  description: "Project-scope session pattern scan",
  prompt: """
    report=SESSION_PROJECT
    harness_root={ROOT}
    cache_dir={CACHE_DIR}
    scope=project, project_dir={PROJECT_ROOT}, days=30, long_session_min=20
    Only this project's sessions (and its live worktrees). tool_use metadata only.
    Return the SESSION_PROJECT JSON as your final message.
  """
)

capability:spawn-named-checker
  checker: "context-quality-reviewer",
  description: "Project context quality review",
  prompt: """
    report=CONTEXT
    harness_root={ROOT}
    cache_dir={CACHE_DIR}
    project_root={PROJECT_ROOT}
    as_of_ms={AS_OF_MS}
    days=30
    Evaluate CLAUDE.md + .claude/rules/* + .gitignore + every hook source + MCP config,
    and the context-audit drift report when present.
    Return the CONTEXT JSON as your final message.
  """
)

capability:spawn-named-checker
  checker: "project-automation-auditor",
  description: "Project automation, verification & compounding audit",
  prompt: """
    report=AUTOMATION
    harness_root={ROOT}
    cache_dir={CACHE_DIR}
    project_root={PROJECT_ROOT}
    as_of_ms={AS_OF_MS}
    days=30
    Audit test/hooks/verifier/isolation from project_signals.py, plus the compounding
    signals it computes.
    Return the AUTOMATION JSON as your final message.
  """
)
```

**For Both scope, spawn all 5 in a single message.** No analyzer reads another's report: the
cross-analyzer items (D4, D5, B4, E2) are joined by check-harness in Phase 2 from the saved
reports.

As each return arrives, save it as-is to `{CACHE_DIR}/<NAME>.json` with `capability:write-file`.
The analyzers never write that file.

### Delegation assertion — required before Phase 2 (divergent-procedure rule)

`capability:spawn-named-checker` is a **divergent** procedure: the two runtimes reach it by
genuinely different means, so parity cannot be guaranteed by running identical bytes. Check every
analyzer spawned in Phase 1 against all four steps below before using any result. Collect every
condition first; then, if any step calls for a halt, halt with the named message (one line per
condition) and print **no score** — a maturity score computed from four of five analyzers,
presented as a score, misrepresents itself.

**1. Spawn return — required evidence.** The analyzer's return must exist and parse as **one JSON
object** carrying its report's analyzer-owned keys (an analyzer does not repeat script-owned
fields):

| Report | Required keys |
|---|---|
| `PORTFOLIO` | `duplicate_clusters`, `trigger_collisions`, `mcp_usage`, `unused_mcp`, `quick_wins`, `script_outputs`, `warnings` |
| `SESSION_USER`, `SESSION_PROJECT` | `scope`, `period_days`, `automation_suggestions`, `script_outputs`, `warnings` |
| `CONTEXT` | `project_root`, `claude_md`, `rules`, `sensitive_protection`, `conditional_load_evidence`, `mcp`, `drift_report`, `script_outputs`, `warnings` |
| `AUTOMATION` | `project_root`, `test_runner_configured`, `test_evidence`, `posttool_format_hook`, `posttool_format_evidence`, `pretool_block_hook`, `pretool_block_evidence`, `verifier_agents`, `isolation`, `risk_findings`, `script_outputs`, `warnings` |

CONTEXT and AUTOMATION may also carry an optional `weak_pass_flags` (`[{field, reason}]`), which the Phase 2 WEAK_PASS rule reads.

A return that is missing, does not parse, or lacks a required key halts the run with
`failed: spawn-named-checker returned no usable result (<analyzer> <NAME>: <reason>)`, naming the
analyzer and report (session-pattern-analyzer runs twice). A return that passes has been saved to
`{CACHE_DIR}/<NAME>.json` (Phase 1).

**2. Registry — recorded, and checked where it says something.** Under Claude Code the spawn is
native and its return is the evidence; there is no registry to query. Under Antigravity, read
`manage_subagents` once after the returns arrive and record what it said, per analyzer:

| Registry says | Evidence grade (kept for the report footer) | Run |
|---|---|---|
| — (Claude Code) | `spawn return (native)` | continues |
| lists this analyzer as defined and invoked | `spawn return + agy registry` | continues |
| empty, or could not be read | `spawn return only (agy registry empty)` (or `… (agy registry unreadable)`) | continues |
| lists other subagents but not this analyzer | — | **halts**: `failed: spawn-named-checker returned no usable result (<analyzer> <NAME>: not in agy registry)` |

An empty registry is observed in some agy sessions and proves nothing either way, so it lowers the
grade instead of failing the run. A registry that lists other subagents but not this one is a real
answer: the report was most likely written in-context, which is exactly the self-graded output
this skill's maker ≠ checker separation exists to prevent.

**3. `script_outputs` status.** For each entry `{script, path, status, exit}` in the return:

| `status` | Effect |
|---|---|
| `ran` | none here — step 4 still reads the file |
| `failed` | that script's fields are N/A with `warning: script failed: <script> exit <exit>` |
| `missing` | that script's fields are N/A with `warning: script failed: <script> missing` |
| `denied` | **halts**: `denied: run-command requires permission not granted (<analyzer> <NAME>: <script>)` |
| `unavailable` | **halts**: `unavailable: run-command not provided by <runtime> (<analyzer> <NAME>: <script>)` |

`denied` and `unavailable` are not script failures: the script never ran, so every item it feeds
would be N/A and the report would look complete while measuring nothing. Only a script that
actually ran and failed takes the N/A path.

**4. Script output files — read from the fixed path, never retyped.** check-harness reads every
script-owned field from the fixed path for that report and script, **whether or not**
`script_outputs` lists it, and never from the analyzer's prose or JSON:

| Report | Fixed-path files under `{CACHE_DIR}/` | `params` must equal |
|---|---|---|
| `PORTFOLIO` | `scratch-PORTFOLIO/inventory.json` | `project_root` = `PROJECT_ROOT` (or `null` when none was passed), `as_of_ms` = `AS_OF_MS`, `dead_days` = 90 |
| | `scratch-PORTFOLIO/session_files.txt` | `scope` = `overall`, `project_dir` = `null` (the prompt passes none), `days` = 30 |
| `SESSION_USER` | `scratch-SESSION_USER/session_files.txt` | `scope` = `overall`, `project_dir` = `null` (the prompt passes none), `days` = 30 |
| | `scratch-SESSION_USER/session_metrics.json` | `session_files` = the same values, `long_session_min` = 20 |
| `SESSION_PROJECT` | `scratch-SESSION_PROJECT/session_files.txt` | `scope` = `project`, `project_dir` = `PROJECT_ROOT`, `days` = 30 |
| | `scratch-SESSION_PROJECT/session_metrics.json` | `session_files` = the same values, `long_session_min` = 20 |
| `CONTEXT` | `scratch-CONTEXT/project_signals.json` | `project_root` = `PROJECT_ROOT`, `as_of_ms` = `AS_OF_MS` |
| `AUTOMATION` | `scratch-AUTOMATION/project_signals.json` | `project_root` = `PROJECT_ROOT`, `as_of_ms` = `AS_OF_MS` |

A `.json` file's `params` is its top-level `params` object; a `session_files.txt` file's is the
JSON on its first line, `# params {json}`. Per file, in order — the first that applies decides:

1. The file does not exist → its fields are N/A with `warning: script output missing: <path>`.
2. It is empty, or does not parse as the script's documented output (a redirect creates the file
   before a crashing script runs) → N/A with `warning: script failed: <script> (unparseable output)`,
   whatever `status` the analyzer reported.
3. Its `params` differs from the values in that spawn's prompt → N/A with
   `warning: script params mismatch: <script>`.
4. Otherwise its fields are the script-owned fields of that report for Phase 2.

When a script that another depends on did not run, the dependent script's fixed-path file is
simply missing, so rule 1 applies. None of these halts the run. Keep every warning from steps 3–4,
every analyzer `warnings` entry (each analyzer copies its scripts' `warning:` stderr lines there;
the raw stderr is kept beside the output as `scratch-<NAME>/<script>.stderr`) and every script's
own `warnings` array: each is listed in the report's findings, and an item fed
by an affected source is N/A with the warning as its evidence.

After all four steps pass, hold in memory: the five saved reports `PORTFOLIO`, `SESSION_USER`,
`SESSION_PROJECT`, `CONTEXT`, `AUTOMATION`; the script output files that passed step 4; the
warnings; the per-analyzer evidence grade; `CACHE_DIR`; and why Project scope is off, if it is.

---

## Phase 2 — Checklist Judgment (6-axis mapping)

For each of the 26 items in `references/checklist.md`, determine PASS/WEAK_PASS/FAIL/N/A and
record an evidence string. Judge only from what the Delegation assertion kept: the saved reports
and the script output files that passed its step 4.

### Per-axis data source mapping

**Source rule.** A report name followed by a **script-owned** field means that field of the
report's fixed-path script file under `{CACHE_DIR}/`; every other field comes from the saved
analyzer return `{CACHE_DIR}/<NAME>.json`. The script-owned files are:

| Written as | Read from |
|---|---|
| `PORTFOLIO.<f>` for `summary`, `plugins`, `mcp_servers`, `skills`, `usage`, `plugin_findings` | `scratch-PORTFOLIO/inventory.json` |
| `SESSION_USER.<f>` / `SESSION_PROJECT.<f>` for `metrics`, `sessions_analyzed`, `skills_invoked`, `commands_invoked`, `agents_invoked`, `automation_opportunities`, `tool_frequency`, … | `scratch-SESSION_USER/session_metrics.json` / `scratch-SESSION_PROJECT/session_metrics.json` |
| `AUTOMATION.<f>` for `hooks`, `planning_artifacts`, `ledgers`, `lessons`, `skills`, `agents`, `checker_citations`, `unattended`, `compounding` | `scratch-AUTOMATION/project_signals.json` |

Per item:

| Axis | Item | Field | Report › file |
|------|------|-------|---------------|
| **1. Scaffolding** (User) | A1, A2, A3 | `PORTFOLIO.summary.used_last_30d`, `total_installed`, `dead_count`, `ghost_count` | PORTFOLIO › `scratch-PORTFOLIO/inventory.json` |
| | A4 | `PORTFOLIO.duplicate_clusters` | PORTFOLIO › `PORTFOLIO.json` |
| | A5 | `PORTFOLIO.summary.prefix_duplicates` + `PORTFOLIO.trigger_collisions` | `inventory.json` + `PORTFOLIO.json` |
| **2. Context** (Project) | C1–C6 | `CONTEXT.claude_md`, `rules`, `sensitive_protection`, `mcp`, `conditional_load_evidence`, `drift_report` (C2), `weak_pass_flags` | CONTEXT › `CONTEXT.json` |
| **3. Planning** (User) | B2 | `SESSION_USER.metrics.plan_first_ratio`; fallback `AUTOMATION.planning_artifacts.exist` | `scratch-SESSION_USER/session_metrics.json`; `scratch-AUTOMATION/project_signals.json` |
| **4. Execution** (User+Project, **each scope separately**) | B3, B5, B6 | `SESSION_*.metrics.delegation_ratio`, `parallel_count`, `top_3gram_share` | `scratch-SESSION_USER/` and `scratch-SESSION_PROJECT/session_metrics.json` |
| **5. Verification** (Project) | B1 | `SESSION_PROJECT.metrics.completion_check_ratio` | `scratch-SESSION_PROJECT/session_metrics.json` |
| | D1, D2, D3 | `AUTOMATION.test_runner_configured` / `test_evidence`, `posttool_format_hook` / `posttool_format_evidence`, `pretool_block_hook` / `pretool_block_evidence`, `weak_pass_flags` | AUTOMATION › `AUTOMATION.json` |
| | D4 (join) | `AUTOMATION.skills[].key`, `AUTOMATION.agents[].key` ∩ `SESSION_PROJECT.skills_invoked`, `commands_invoked`, `agents_invoked` | `project_signals.json` ∩ `scratch-SESSION_PROJECT/session_metrics.json` |
| | D5 (join) | Set up: `AUTOMATION.verifier_agents` (`AUTOMATION.json`), `AUTOMATION.checker_citations` (`project_signals.json`); Used: `SESSION_PROJECT.skills_invoked`, `commands_invoked`, `agents_invoked` | `AUTOMATION.json` + `project_signals.json` + `scratch-SESSION_PROJECT/session_metrics.json` |
| | D6 | `AUTOMATION.unattended.conforming`, `unattended.autopilot_files` | `scratch-AUTOMATION/project_signals.json` |
| **6. Compounding** (Both) | E1, E3 | `AUTOMATION.compounding.*`, `AUTOMATION.lessons.updated_30d`, `lessons.hardened_added_90d`; `AUTOMATION.ledgers` as evidence | `scratch-AUTOMATION/project_signals.json` |
| | B4 | `SESSION_*.metrics.handoff_ratio` | each `session_metrics.json` |
| | E2 (join) | `SESSION_*.metrics.learning_write_sessions`, `SESSION_*.skills_invoked`, `commands_invoked` | both `session_metrics.json` |

The report's other sections read: Runtime inventory ← `PORTFOLIO.plugins`, `mcp_servers`,
`skills`, `plugin_findings` (`inventory.json`) and `PORTFOLIO.mcp_usage`, `unused_mcp`,
`quick_wins` (`PORTFOLIO.json`); Execution Detail ← `SESSION_*.sessions_analyzed` and
`metrics.*` (`session_metrics.json`) and `SESSION_*.automation_suggestions` (the saved return).

### Axis 4 (Execution) note

B3/B5/B6 record **both User and Project values**. Axis-level judgment follows this rule:
- Both scope: use the **lower** of User/Project for axis judgment (weakest link principle)
- Single scope: use only that scope's value

B4 likewise records a User and a Project value (Axis 6's User and Project portions); E1, E3 and D6
are Project values; E2 is one value over both session reports.

### Status rules

- **PASS** — evidence clearly met
- **WEAK_PASS** — condition met but the report flags it in `weak_pass_flags`, or an item rule
  below says WEAK_PASS
- **FAIL** — no evidence or explicit failure
- **N/A** — no data available (e.g., 0 sessions, a `null` ratio), not applicable to the project
  type, or a **source the item depends on carries a warning**: `source missing`, `unexpected
  shape`, `git unavailable` (the git-derived fields are `null`), `script failed`, `script output
  missing` or `script params mismatch` (Delegation assertion steps 3–4). The evidence string is the
  warning itself. A `null` field is never read as `false` or 0.
- **OR rules** (B2, E1, E2, E3): PASS when any available term passes; FAIL only when every term
  was available and none passes; otherwise N/A, naming the warning of the missing term.

### Item rules that combine reports (Phase 2 joins)

No analyzer reads another's report (all are spawned in one message), so check-harness computes
these joins itself, from the sources in the table above. Keys are compared exactly as the scripts
printed them (normalised D3 keys, e.g. `harness-ops:loop` vs the built-in `loop`).

**Role match.** A key matches a role list when it equals a full key in the list, or when it is
bare, is not a built-in, and equals a listed skill part (a user's own standalone `specify`
counts). A built-in counts only when the list names it explicitly as a bare built-in — the
built-in `/loop` scheduler never counts as `harness-ops:loop`.

- **B2 — plan first** (OR): `SESSION_USER.metrics.plan_first_ratio ≥ 0.3` → PASS, evidence
  `"plan_first_ratio: X.XX"`; or `AUTOMATION.planning_artifacts.exist == true` → PASS, evidence
  the non-zero kinds, e.g. `"planning artifacts: spec 7, design 1"`. With no AUTOMATION
  (User-scope-only run) evaluate the ratio only, with no error.
- **C2 — CLAUDE.md quality** (one judge; the drift report corroborates):
  `CONTEXT.claude_md.quality.contradictions > 0` → FAIL. Contradictions 0, and
  `CONTEXT.drift_report` is not `null`, its `generated` falls within 30 days of `AS_OF_MS` and
  its `contradictions ≥ 1` → WEAK_PASS, evidence `drift_report.path`. Otherwise, with
  contradictions 0:
  - `ambiguities` and `placeholders` both 0 → PASS (WEAK_PASS when `weak_pass_flags` names
    `claude_md.quality`);
  - `ambiguities ≥ 1` or `placeholders ≥ 1` → WEAK_PASS, evidence the two counts and the first
    `ambiguity_examples` entry. Only a contradiction fails C2: a vague phrase or a leftover TODO
    makes an instruction weaker, while a contradiction makes two instructions incompatible.

  A `generated` that is `null` or cannot be read as a date is not within 30 days; a
  `drift_report.contradictions` of `null` does not count.
- **D4 — project skills/agents used**: registered = `AUTOMATION.skills[].key` and
  `AUTOMATION.agents[].key`. PASS when ≥ 1 skill key is in `SESSION_PROJECT.skills_invoked ∪
  commands_invoked` or ≥ 1 agent key is in `SESSION_PROJECT.agents_invoked`, evidence the
  matched keys with counts; FAIL when none is; N/A when Project scope is off or SESSION_PROJECT
  is N/A.
- **D5 — separate checker set up and used**:
  - *Set up* = `AUTOMATION.verifier_agents` is non-empty (the auditor already excludes
    check-harness's four analyzers) or `AUTOMATION.checker_citations` is non-empty.
  - *Used* = a key in `SESSION_PROJECT.skills_invoked ∪ commands_invoked` role-matches
    `harness-ops:specify`, `harness-ops:loop`, `harness-ops:coherence-audit`, `harness-ops:crew`
    or `harness-ops:agent-orchestrate`, or is the built-in `code-review`; or a `verifier_agents`
    key is in `SESSION_PROJECT.agents_invoked`.
  - Set up and used → PASS; only one → WEAK_PASS; neither → FAIL. When SESSION_PROJECT is N/A,
    *Used* is unknown: set up → WEAK_PASS, not set up → N/A (the OR rule: FAIL only when every
    term was available), with the warning in the evidence.
- **D6 — unattended runs are bounded**: `AUTOMATION.unattended.conforming` `null` (no real-ledger
  `autopilot.md`) → N/A; `true` → PASS, evidence the file count; `false` → FAIL, evidence each
  `unattended.autopilot_files[].path` with its `missing_limits`.
- **E1 — learning written back** (OR): `AUTOMATION.compounding.claude_md_updated_30d`,
  `compounding.rules_added_90d > 0`, `compounding.docs_learnings_exist`, or
  `AUTOMATION.lessons.updated_30d`.
- **B4 — handoff**: per scope, `SESSION_*.metrics.handoff_ratio ≥ 0.5` (among long sessions).
- **E2 — learning recorded** (OR, over both session reports): `metrics.learning_write_sessions ≥ 1`
  in SESSION_USER or SESSION_PROJECT, or any key in `skills_invoked ∪ commands_invoked` of either
  whose skill part is `session-wrap`, `wrap`, `compound`, `remember` or `handoff` (any owner).
- **E3 — artifact added in 90 days** (OR): `AUTOMATION.compounding.skills_added_90d ≥ 1`,
  `compounding.hooks_added_90d ≥ 1`, `compounding.agents_added_90d ≥ 1`, or
  `AUTOMATION.lessons.hardened_added_90d ≥ 1`.

Every other item follows its Judgment Basis in `references/checklist.md`, read through the source
table above.

### Maturity calculation

**Per-axis level**
- All L1 items PASS/WEAK_PASS → L1 achieved
- All L2 items also PASS → L2, L3 also → L3

**User Maturity** = min(axis 1, axis 3, axis 4-User portion, axis 6-User portion)
**Project Maturity** = min(axis 2, axis 4-Project portion, axis 5, axis 6-Project portion)

**Score (per axis, 0–100)**
- Item score: PASS=1, WEAK_PASS=0.5, FAIL=0, N/A=excluded
- Weights: L1×3, L2×2, L3×1
- Axis score = Σ(score × weight) / Σ(weight) × 100

**Harness Score**
- User Score = mean(axis 1, axis 3, axis 4-User)
- Project Score = mean(axis 2, axis 4-Project, axis 5)
- Compounding (axis 6) is reported as an **independent axis score** rather than being added to User/Project (accumulation is a time axis — point-in-time aggregation would distort)
- **Harness Score** = (User + Project + Compounding) / 3 (when Both scope)
- Grade: 90+ Excellent / 75+ Good / 60+ Fair / <60 Needs Work

**Progress to next level**: `passing items at current level / items required for next level`

---

## Phase 2.5 — TL;DR & Action Synthesis

Using Phase 2 judgments as input, generate the key summary for the top of the report first.

### 5 variables to generate

1. **`headline`** (1 sentence) — User/Project maturity + "biggest problem" + "easiest starting point"
   e.g.: *"User L2 / Project L1 — CLAUDE.md is missing run commands and the compounding axis is thin. Start by adding 3 lines of dev commands."*

2. **`cycle_line`** (6 items, 1 line each) — per-axis one-liner in cycle order:
   - `1. Scaffolding — {one line}`
   - `2. Context — {one line}`
   - `3. Planning — {one line}`
   - `4. Execution — {one line, may include User/Project comparison}`
   - `5. Verification — {one line}`
   - `6. Compounding — {one line}`

3. **`strength`** (1 sentence) — strength drawn from axes with few FAILs and many PASSes.

4. **`weakness`** (1 sentence) — weakness from axes with concentrated FAILs.

5. **`actions`** (3–7 items) — 3-tier classification:
   - 🟢 **Quick Wins**: single command / one-line change
   - 🟡 **Worth Organizing**: edit one file
   - 🔴 **Long-term Improvements**: structural changes

### Selection rules

- High Priority Finding → must be included
- Prioritize items with a clear command/file path
- Remove duplicates
- Maximum 7 items
- **Include at least 1 suggestion based on Runtime inventory (PORTFOLIO)**
- **Include at least 1 suggestion when Compounding (axis 6) FAILS** — e.g., "add what you learned this session to rules/"
- **D6 FAIL → always an action** naming each `autopilot.md` and the limits it lacks (an unbounded unattended run is the costliest finding)
- Every warning kept by the Delegation assertion appears in the findings list, even when it produced no action

### Action tone enforcement

- ❌ "X is missing" / "X is insufficient" / "You must do X"
- ✅ "Adding X will {effect}" / "Doing X makes things easier"
- Each action includes an `Expected effect:` field

---

## Phase 3 — Report Generation (3 deliverables)

**Top-heavy + cycle narrative + per-axis detail**: fast at the top, progressively richer per axis below.

**Generate all 3 deliverables simultaneously**:
- **A. Conversation render** (markdown template below) — output immediately
- **B. report.md** (same content as A) — Write to `{REPORT_DIR}/report.md`
- **C. report.html** (based on references/html-template.html, self-contained) — Write to `{REPORT_DIR}/report.html`, then `open`

### A/B Markdown template (shared for conversation + report.md)

```markdown
# 🧭 Harness Maturity Report

**{YYYY-MM-DD}** · Scope: `{user|project|all}` · Project: `{name or "-"}`

---

## 🧭 Harness Score: **{NN} / 100**  ({Excellent|Good|Fair|Needs Work})

```
👤 User Scope    L{n}  ▓▓▓▓▓▓▓░░░  {XX}% → L{n+1}   (Score: {NN})
📁 Project Scope L{n}  ▓▓▓▓▓▓▓▓░░  {XX}% → L{n+1}   (Score: {NN})
🔁 Compounding   L{n}  ▓▓▓▓░░░░░░  {XX}% → L{n+1}   (Score: {NN})
```

> User = `~/.claude/` global (Scaffolding·Planning·Execution-User axes)
> Project = this project (Context·Verification·Execution-Project axes)
> Compounding = whether the harness is growing (axis 6, shared)

## 🎯 Summary

> {headline}

**Strengths**: {strength}
**Areas to Improve**: {weakness}

---

## 🔄 Cycle Overview

> One line per axis in Scaffolding → Context → Planning → Execution → Verification → Compounding order.

1. **Scaffolding** · 👤 User — {cycle_line[0]}
2. **Context** · 📁 Project — {cycle_line[1]}
3. **Planning** · 👤 User — {cycle_line[2]}
4. **Execution** · 👤+📁 — {cycle_line[3]}
5. **Verification** · 📁 Project — {cycle_line[4]}
6. **Compounding** · 👤+📁 — {cycle_line[5]}

---

## ✅ Recommended Actions

> Pick any that feel manageable. Each action shows **scope (👤/📁)**.

### 🟢 Quick Wins
- [ ] {👤|📁} **{action}** — Expected effect: {benefit}
  - Command: `{copy-paste command}`
  - Evidence: {evidence}

### 🟡 Worth Organizing
- [ ] {👤|📁} **{action}** — Expected effect: {benefit}
  - Reference: {file path}
  - Evidence: {evidence}

### 🔴 Long-term Improvements
- [ ] {👤|📁} **{action}** — Expected effect: {benefit}
  - Evidence: {evidence}

---

## 📊 Scorecard (6 Axes)

| Axis | Scope | Score | Level | To next level |
|------|-------|------:|:-----:|:-------------|
| 1. Scaffolding      | 👤 User     | {NN} | L{n} | {XX}% → L{n+1} |
| 2. Context          | 📁 Project  | {NN} | L{n} | {XX}% → L{n+1} |
| 3. Planning         | 👤 User     | {NN} | L{n} | {XX}% → L{n+1} |
| 4. Execution        | 👤+📁        | {NN} | L{n} | {XX}% → L{n+1} |
| 5. Verification     | 📁 Project  | {NN} | L{n} | {XX}% → L{n+1} |
| 6. Compounding      | 👤+📁        | {NN} | L{n} | {XX}% → L{n+1} |

Sessions analyzed: User {Nu} / Project {Np} (one period for both: last 30 days) · Scanned: {YYYY-MM-DD HH:MM}

---

## 🔌 Active Runtime State (Runtime Inventory)

> What is **actually accessible** in this Claude Code session right now.

**📦 Plugins** ({enabled_project}/{installed} enabled in this project)
| Plugin | Version | Scope | Skills | Usage last 30d |
|--------|:-------:|:-----:|------:|:--------------|
| ... | ... | 👤📁 | ... | ... |

**🔗 MCP Servers** ({total} total · {unused} unused)
| Server | Scope | Type | Recent calls |
|--------|:-----:|:----:|:--------:|
| ... | ... | ... | ... |

**🧩 Skill origins**
- User standalone: {N}
- Via plugin: {N}
- Project local: {N}

---

<details>
<summary>🧭 2×3 Analysis Matrix (Static/Behavioral/Growth × User/Project)</summary>

|  | Static (set up) | Behavioral (doing) | Growth (accumulating) |
|---|---|---|---|
| 👤 User    | Axis 1 (Score {NN}) | Axis 3 · Axis 4-User (Score {NN}/{NN}) | Axis 6-User (Score {NN}) |
| 📁 Project | Axis 2 (Score {NN}) | Axis 4-Project · Axis 5 (Score {NN}/{NN}) | Axis 6-Project (Score {NN}) |

**Gap summary from cross-analysis**
- Static vs Behavioral (User): {N skills installed but unused → B2 plan-first ratio low}
- Static vs Behavioral (Project): {hook exists but 0 calls / hook needed but absent}
- Growth: {N artifact updates in last 30 days → accumulation status}

</details>

<details>
<summary>📋 Full Checklist (6 axes · 26 items)</summary>

### Axis 1 — Scaffolding (👤 User × Static)
| ID | L | Item | Status | Evidence |
|----|---|------|--------|----------|
| A1 | L1 | 70%+ skills used last 30d | PASS | ... |
| ... |

### Axis 2 — Context (📁 Project × Static)
...

### Axis 3 — Planning (👤 User × Behavioral)

> **B2 judgment rule** (OR condition):
> 1. `SESSION_USER.metrics.plan_first_ratio ≥ 0.3` → PASS, evidence: `"plan_first_ratio: X.XX"`
> 2. `AUTOMATION.planning_artifacts.exist == true` → PASS, evidence: the non-zero kinds, e.g. `"planning artifacts: spec 7, design 1"` — counts from `scratch-AUTOMATION/project_signals.json`
> 3. AUTOMATION absent (User-scope-only run) → evaluate (1) only, no error
> 4. Both false → FAIL

...

### Axis 4 — Execution (👤+📁 × Behavioral)
> Show both User and Project values

| ID | L | Item | User | Project | Status(min) | Evidence |
|----|---|------|------|---------|-------------|----------|
| B3 | L2 | delegation_ratio ≥ 0.4 | 0.55 | 0.20 | FAIL(project) | ... |
| ... |

### Axis 5 — Verification (📁 Project)
| ID | L | Item | Status | Evidence |
|----|---|------|--------|----------|
| B1 | L1 | completion check before session end | PASS | completion_check_ratio: 0.62 |
| D1 | L1 | test environment | PASS | Makefile:test |
| D2 | L1 | formatter/linter PostToolUse hook | FAIL | no formatting hook in any source |
| D3 | L1 | dangerous actions blocked (PreToolUse) | PASS | project PreToolUse/Bash: block-main-push.sh |
| D4 | L2 | project skills/agents actually used | PASS | harness-ops:loop ×4, git-operator ×2 |
| D5 | L3 | separate checker set up and used | WEAK_PASS | set up: checker_citations 3 · used: none in project sessions |
| D6 | L3 | unattended runs are bounded | FAIL | specs/x/autopilot.md missing killswitch_path |

### Axis 6 — Compounding (👤+📁 × Growth)
| ID | L | Item | Status | Evidence |
|----|---|------|--------|----------|
| E1 | L1 | CLAUDE.md/rules/docs/loop lessons updated recently | PASS | CLAUDE.md updated within 30d |
| B4 | L2 | handoff ratio (long sessions) | FAIL | User 0.42 / Project 0.60 |
| E2 | L2 | learning write or wrap-type skill ≥1 | PASS | learning_write_sessions: 3 |
| E3 | L3 | new skill/hook/agent or hardened lesson in last 90d | PASS | skills_added_90d: 2, hardened_added_90d: 1 |

</details>

<details>
<summary>🔍 Full Findings List</summary>

**High Priority**
- 💡 {...}

**Medium Priority**
- 💡 {...}

**Low Priority**
- 💡 {...}

</details>

<details>
<summary>🧩 Skill Portfolio Detail (👤 User × Static)</summary>

Total installed skills: {N} · Used last 30d: {X} ({%})

| Category | Count | Description | Examples |
|----------|------:|-------------|---------|
| 😴 Long unused (90d+) | N | ... | ... |
| 👻 Ghost entries only | N | ... | ... |
| 🔁 Duplicate purpose clusters | N | ... | ... |
| 🏷️ Namespace duplicates | N | ... | ... |
| ⚠️ Trigger collisions | N | ... | ... |

</details>

<details>
<summary>⚡ Execution Detail (Session habits — User vs Project, one 30-day period)</summary>

|                          | 👤 User | 📁 Project |
|--------------------------|-------:|-----------:|
| plan-first ratio         | {X}%   | {X}%       |
| delegation ratio         | {X}%   | {X}%       |
| parallel calls           | {N}    | {N}        |
| handoff ratio            | {X}%   | {X}%       |
| completion check ratio   | {X}%   | {X}%       |
| top 3-gram share         | {X}%   | {X}%       |
| sessions analyzed        | {N}    | {N}        |

Period: last 30 days for both columns (`days=30` in both session scans).

**Automation candidates (repeated patterns)**
- User: `Read → Edit → Bash(npm test)` — {N} times
- Project: `...` — {N} times

</details>

<details>
<summary>🔁 Compounding Detail (Axis 6 — harness accumulation)</summary>

- CLAUDE.md updated in last 30d: {Yes/No} ({commit evidence})
- `.claude/rules/` additions in last 90d: {N}
- `skills/` additions in last 90d: {N}
- `hooks/` changes in last 90d: {N}
- `agents/` additions in last 90d: {N}
- `docs/learnings/` exists: {Yes/No}
- Loop lessons: {N} real `loop.md` ledgers · updated in last 30d: {Yes/No} · hardened lessons added in last 90d: {N}
- Durable ledgers: `build_order.md` {N} · `pipeline.md` {N} · `autopilot.md` {N} (conforming: {Yes/No/-})
- learning writes / wrap-type invocations in sessions: User {N} / Project {N}

**Observations**
- {e.g., no new rules added to this project recently → learning exists only in the human's head}

</details>

Period: last 30 days (User and Project) · Cache: `{CACHE_DIR}` · Evidence: {PORTFOLIO: grade · SESSION_USER: grade · SESSION_PROJECT: grade · CONTEXT: grade · AUTOMATION: grade}{ · Project scope off: reason}

📁 Saved: {dir}/ · 🌐 Opened: report.html
```

### Conversation render expansion rules (A block)

When outputting to the conversation, render each axis section with more detail. Per axis:

```
### {N}. {Axis name} · {Scope emoji} · {Status summary}
Score: {NN}/100  L{n}  ▓▓▓▓▓▓▓░░░ {XX}% → L{n+1}

Key findings:
- ✅ {1–2 things going well, with supporting numbers}
- ⚠️ {1–2 improvement points, with supporting numbers}

Checklist:
| ID | L | Item | Status | Evidence |
|----|---|------|--------|----------|
| {row} |

Cheapest next move: {quick win + command or path}
```

Same structure for all 6 axes. Each axis section should be 5–12 lines.

### C block — HTML report generation

The template (`references/html-template.html`) is a self-contained dark dashboard: top bar → **SVG ring hero** (ring + 6 cycle nodes) → cycle strip → 6 axis cards → recommended next moves → runtime inventory + 2×3 matrix → 3-column findings → footer. It loads Space Grotesk + IBM Plex Mono from Google Fonts with a system-font fallback, and defines status colors as CSS vars (`--green` `oklch(0.78 0.12 155)`, `--amber` `oklch(0.82 0.12 82)`, `--coral` `oklch(0.70 0.15 22)`, `--accent` `oklch(0.74 0.12 262)`, `--na` `#6b7280`) plus the four grade-pill classes.

1. Read `references/html-template.html`.
2. Replace **every** placeholder below (the template and this list must stay in 1:1 parity — no orphan tokens, and a finished render must contain no literal `{{`):

   **Scalars**
   - `{{GENERATED_AT}}`, `{{SCOPE}}`, `{{PROJECT_NAME}}`
   - `{{HARNESS_SCORE}}` (plain integer 0–100, no `%`), `{{HARNESS_GRADE}}` (text: `Excellent|Good|Fair|Needs Work`)
   - `{{HEADLINE}}`, `{{STRENGTH}}`, `{{WEAKNESS}}`
   - `{{USER_SCORE}}`, `{{USER_LEVEL}}`, `{{PROJECT_SCORE}}`, `{{PROJECT_LEVEL}}`, `{{COMPOUNDING_SCORE}}`, `{{COMPOUNDING_LEVEL}}` (scores are plain integers; they also drive mini-bar widths via `width:{{…}}%`)
   - `{{SESSION_ID}}`
   - `{{PERIOD}}` — the one session window, `last 30 days` (User and Project alike)
   - `{{CACHE_DIR}}` — this run's `CACHE_DIR` (Phase 0)
   - `{{DELEGATION_EVIDENCE}}` — the per-analyzer evidence grade from the Delegation assertion, e.g. `PORTFOLIO spawn return (native) · SESSION_USER spawn return (native) · …` (spawned analyzers only)

   **Ring + grade (computed — see below)**
   - `{{RING_DASHARRAY}}` — the two-value SVG dash for the progress arc
   - `{{GRADE_CLASS}}` — one of `grade-excellent | grade-good | grade-fair | grade-needs-work`
   - `{{NODE1_COLOR}}`, `{{NODE2_COLOR}}`, `{{NODE3_COLOR}}`, `{{NODE4_COLOR}}`, `{{NODE5_COLOR}}`, `{{NODE6_COLOR}}` — the 6 cycle-node fill colors

   **Generated blocks (emit inner HTML; on an empty list emit a single `None` item — never leave the slot blank or tokenized)**
   - `{{CYCLE_STRIP}}` — 6 stage cards (cycle-card markup below)
   - `{{AXIS_CARDS}}` — 6 axis `<article>` cards (axis-card markup below)
   - `{{ACTIONS_GREEN}}`, `{{ACTIONS_YELLOW}}`, `{{ACTIONS_RED}}` — `<li>` action items (action-item markup below)
   - `{{INVENTORY_TABLE}}`, `{{MATRIX_TABLE}}` — runtime inventory blocks / 2×3 matrix grid
   - `{{FINDINGS_HIGH}}`, `{{FINDINGS_MEDIUM}}`, `{{FINDINGS_LOW}}` — `<li>` finding items (finding-item markup below)
3. Write, then `capability:run-command` → `open {dir}/report.html` — opens in the default browser.

#### Ring, node, and grade computation

- **`{{RING_DASHARRAY}}`** = `"{filled} 880"` where `filled = round(HARNESS_SCORE / 100 * 880)` (the ring is `r=140`, circumference ≈ 879.6). Two values are required — a single value would tile the dash instead of drawing one progress arc. Example: score 68 → `"598 880"`.
- **`{{NODE1_COLOR}}` … `{{NODE6_COLOR}}`** map **node N → axis N in cycle order** (1=Scaffolding, 2=Context, 3=Planning, 4=Execution, 5=Verification, 6=Compounding). Each value is that axis's rolled-up **status color**: PASS→`oklch(0.78 0.12 155)`, WEAK→`oklch(0.82 0.12 82)`, FAIL→`oklch(0.70 0.15 22)`, N/A→`#6b7280` (same palette as the axis-card border-left, matching the template's `--green/--amber/--coral/--na`).
- **`{{GRADE_CLASS}}`** from the score bucket: `≥90 → grade-excellent`, `≥75 → grade-good`, `≥60 → grade-fair`, `<60 → grade-needs-work`. `{{HARNESS_GRADE}}` carries the matching visible text.

#### Status → color reference (used by all emitted blocks)

| Status | Accent color | Badge bg | Badge text |
|--------|--------------|----------|------------|
| PASS | `oklch(0.78 0.12 155)` | `rgba(95,207,154,0.16)` | green |
| WEAK | `oklch(0.82 0.12 82)` | `rgba(221,192,102,0.16)` | amber |
| FAIL | `oklch(0.70 0.15 22)` | `rgba(232,122,130,0.16)` | coral |
| N/A | `#6b7280` | `rgba(107,114,128,0.16)` | `#6b7280` |

#### Cycle stage card (×6, into `{{CYCLE_STRIP}}`) — `border-top` = axis status accent color

```html
<div style="background:#1a1e28;border:1px solid #272c38;border-top:2px solid {accent};border-radius:10px;padding:13px 13px 14px;">
  <div style="display:flex;align-items:center;gap:7px;margin-bottom:8px;"><span style="font:600 11px/1 var(--font-mono);color:#8a93a6;">0{N}</span><span style="font:600 13px/1 var(--font-display);">{Axis name}</span></div>
  <div style="font-size:11.5px;line-height:1.45;color:#aab2c2;">{✅|⚠️|❌} {one-liner + one supporting number}</div>
</div>
```

#### Axis card (×6, into `{{AXIS_CARDS}}`) — `border-left` + score bar + node share the axis accent color

```html
<article style="background:#13161e;border:1px solid #272c38;border-left:3px solid {accent};border-radius:14px;padding:17px 18px;display:flex;flex-direction:column;gap:11px;">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;">
    <div>
      <div style="display:flex;align-items:center;gap:8px;"><span style="font:600 11px/1 var(--font-mono);color:#8a93a6;">0{N}</span><h3 style="margin:0;font:600 15px/1.1 var(--font-display);">{name}</h3></div>
      <div style="font:500 11px/1 var(--font-mono);color:#8a93a6;margin-top:5px;">{scope label, e.g. 👤 User · Static}</div>
    </div>
    <div style="text-align:right;min-width:84px;">
      <div style="display:flex;align-items:baseline;justify-content:flex-end;gap:6px;"><span style="font:700 21px/1 var(--font-display);letter-spacing:-0.02em;">{score}</span><span style="font:500 11px/1 var(--font-mono);color:#8a93a6;">L{n}</span></div>
      <div style="height:5px;width:84px;background:#272c38;border-radius:3px;overflow:hidden;margin-top:7px;"><span style="display:block;height:100%;width:{score}%;background:{accent};border-radius:3px;"></span></div>
    </div>
  </div>
  <p style="margin:0;font-size:13px;line-height:1.5;color:#cfd5e2;text-wrap:pretty;">{headline}</p>
  <details style="background:#0f1218;border:1px solid #232834;border-radius:9px;padding:9px 12px;">
    <summary style="font:500 12px/1 var(--font-mono);color:#8a93a6;display:flex;align-items:center;justify-content:space-between;">Checklist <span style="color:#6b7280;">{e.g. 3 pass · 2 weak}</span></summary>
    <table style="width:100%;border-collapse:collapse;margin-top:10px;">
      <!-- one <tr> per checklist row: -->
      <tr style="border-top:1px solid #1f2430;">
        <td style="padding:6px 7px 6px 0;vertical-align:top;font:500 11px/1.3 var(--font-mono);color:#6b7280;white-space:nowrap;">{id}<br /><span style="color:#4d5564;">{L1|L2|L3}</span></td>
        <td style="padding:6px 7px;vertical-align:top;font-size:12px;line-height:1.35;">{item}<div style="color:#8a93a6;font:400 11px/1.35 var(--font-mono);margin-top:2px;">{evidence}</div></td>
        <td style="padding:6px 0 6px 7px;vertical-align:top;text-align:right;white-space:nowrap;"><span style="display:inline-block;padding:2px 8px;border-radius:11px;font:600 10px/1.4 var(--font-mono);background:{badgeBg};color:{badgeColor};">{PASS|WEAK|FAIL|N/A}</span></td>
      </tr>
    </table>
  </details>
  <div style="display:flex;align-items:flex-start;gap:7px;font-size:12.5px;line-height:1.45;color:var(--accent);"><span style="flex-shrink:0;">→</span><span style="text-wrap:pretty;">{next move}</span></div>
</article>
```

#### Action item (`<li>`, into `{{ACTIONS_GREEN/YELLOW/RED}}`) — lead with scope emoji; `<code>` is optional

```html
<li style="background:#13161e;border:1px solid #272c38;border-radius:9px;padding:11px 12px;">
  <div style="font-size:13px;font-weight:600;line-height:1.4;">{👤|📁|👤📁} {action title}</div>
  <div style="font-size:11.5px;color:#8a93a6;line-height:1.45;margin-top:4px;">{expected effect}</div>
  <code style="display:inline-block;margin-top:8px;font:500 11px/1.4 var(--font-mono);background:#0f1218;border:1px solid #232834;padding:3px 7px;border-radius:5px;color:#cfd5e2;">{command or path}</code>
</li>
```

#### Finding item (`<li>`, into `{{FINDINGS_HIGH/MEDIUM/LOW}}`) — bullet color = coral / amber / muted by priority

```html
<li style="font-size:12.5px;line-height:1.5;color:#cfd5e2;padding-left:16px;position:relative;text-wrap:pretty;"><span style="position:absolute;left:0;color:{coral|amber|#8a93a6};">💡</span>{one suggestion sentence}</li>
```

#### Inventory + matrix

- **`{{INVENTORY_TABLE}}`** — emit the Plugins table (name · scope · skills · 30d use), the MCP-servers block, and the Skill-origins counters (user standalone / via plugin / project local), inline-styled to match the surrounding panels. Empty section → a single `None configured` line.
- **`{{MATRIX_TABLE}}`** — emit the 2×3 grid: rows 👤 User / 📁 Project × columns Static / Behavioral / Growth (Growth cell spans both rows), each cell showing the axis label + score, plus the "Gap read" summary line.

**Empty-list rule (all generated blocks):** if a list (actions, findings, inventory rows) has zero items, emit a single muted `None` item — never leave a placeholder unreplaced.

### Report tone guide

- **No verdict sentences** — "X is missing" ❌
- **Use suggestion sentences** — "Adding X will {effect}" ✅
- Findings labels are unified as **💡 emoji + one suggestion sentence**
- Each action in "Recommended Actions" must include a **copy-pasteable command** or **file path**
- Each line in "Cycle Overview" must include **status (✅/⚠️/❌) + one supporting number**

---

## Hard Rules

1. **Do not read prompt content** — session-pattern-analyzer uses tool_use metadata only
2. **Do not modify project files** — write only reports, and only into this run's own `{REPORT_DIR}` under `.harness/check-reports/`, and this run's `{CACHE_DIR}/<NAME>.json` (analyzers write only their own `{CACHE_DIR}/scratch-<NAME>/`)
3. **Evidence-based evaluation** — every status must include an evidence string
4. **Context awareness** — mark N/A for items not applicable to the project type
5. **Parallel execution** — Phase 1 subagents must be spawned in the same message (5 at once for Both scope)
6. **Separate User/Project sessions** — call session-pattern-analyzer separately per scope (SESSION_USER, SESSION_PROJECT)
7. **Axis 6 (Compounding) is a Growth axis** — report as an independent score, not summed with User/Project (time derivative, not a point-in-time aggregate)
8. **Cache reuse** — this run's `CACHE_DIR` (created by `mktemp -d` in Phase 0, printed in the report footer) holds the 5 saved reports and the `scratch-<NAME>/` script outputs; they can be reused in follow-up analysis of this run. Never read another run's directory as this run's data
