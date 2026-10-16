# Requirement Check — formats and prompt templates

Used by `skills/agent-orchestrate/SKILL.md` › `## Unattended Mode` (Phase 3 "run TT tasks first",
Phase 3.4 "Requirement Check", and the re-dispatch rounds). Interactive runs never read this
file. Everything here is written or read by the orchestrator; workers and the checker only
receive the prompts below and return text.

**Identification.** A TT task is one whose id matches `TT\d+` (equivalently, whose `Fulfills`
contains `(tests)`). Every other task, including `[infra]`, is an implementation task. Signal
exclusion, TT-first execution, park non-propagation, and re-dispatch targeting all use this key.

**Where the procedures live.** This file holds formats and prompt templates only. What the
orchestrator *does* — the TT snapshot check and its cleanup, the HEAD guard, re-dispatch
targeting, the recheck after the gate, run identity, and the resume rules — is stated once, in
SKILL.md `## Unattended Mode`, and is not repeated here: two hand-kept copies of that control
flow drift apart.

## 1. `gwt-tests.md` — GWT to test mapping

Path: `{specDir}/gwt-tests.md`. **The orchestrator is the single writer.** TT workers return
text (section 3) and never touch this file; parallel TTs writing one file would lose updates.
The orchestrator creates the file with the `spec:` line (run identity, §2) and the R0 block, then
appends one block each time a TT finishes — so on resume a TT that already has a block is not
re-run, and one without a block is.

Hashes are **measured by the orchestrator** with `shasum -a 256` on each file in the TT's
returned list, after the return is checked against the tree and the files are formatted
(SKILL.md TT-first step 2); a TT never returns hashes. Next to each hash goes the blob id from
`git hash-object -w`, which stores the file's content in the object store: the known-good copy
a changed or deleted listed file is restored from.

```markdown
# gwt-tests — {spec name}
spec: sha256 {64 hex of spec.md}

## R0 — (no TT)
- R0.1: manual: goal-level
- R0.2: manual: goal-level

## TT2 — R2 — L2: D3, D4
- run: `pytest tests/tt2_projects_api_test.py`
- R2.1: test: tests/tt2_projects_api_test.py::test_create_returns_201
- R2.2: test: tests/tt2_projects_api_test.py::test_list_empty_at_start
- R2.3: manual: no spec-named boundary
- files:
  - tests/tt2_projects_api_test.py  sha256: {64 hex}  blob: {40 hex}

## TT3 — R3 — L2: D5
- run: none
- R3.1: manual: no test runner
- files: none
```

Each block: the TT id, its Rn, the L2 ids the TT copied from the `### Rn` heading; one `run:`
line (`none` when every GWT is manual); one line per sub-requirement, `test: {file}::{case}`
or `manual: {reason}`; the file list with one hash and one blob id per file. Statuses only the orchestrator
writes: `manual: goal-level` (R0 has no TT, so no return value), `manual: TT failed — {reason}`
and `manual: TT fenced — {reason}` (the TT errored, timed out, or reported FENCED — a block
with no run line and no files; Rn's implementation tasks still run), and `manual: parked`
(every implementation task of Rn became parked after the TT ran; the TT's files are removed
at the same time, the block keeps no run line and no files, and those GWTs leave the check
scope — a removed file left in the list would fail SKILL.md Phase 4.2's hash re-measure).

## 2. `requirement-check.md` — round ledger

Path: `{specDir}/requirement-check.md`. Every entry is written by the orchestrator by **atomic
write**: the whole new content to `{specDir}/requirement-check.md.tmp`, then rename over the
target. The file is the resume state for the run (the counterpart of loop's `progress.md`). It
is never committed: `specs/` is usually gitignored, and where it is not, Phase 4.2's scope check
leaves the file out. The TT snapshot check and the checker's changed-file list leave it out too,
along with `gwt-tests.md` and the report.

Entries, in the order they appear (SKILL.md says when each is written and what each means on
resume — Phase 3 park step 2, the HEAD guard, Phase 3.4 step 5, Phase 3.5, Phase 4.2):

1. `spec: sha256 {hash of spec.md}` — the line right under the `#` heading: the run identity.
2. `head: {sha} on {branch}` — `HEAD` and the branch when the file is created, before Phase 3
   runs any task; the HEAD guard compares against it.
3. Task events: `task {id} parked — {reason}`; `task {id} blocked {GWT} — {reason}`; `task {id}
   done` (Patterns A–C, Phase 3 only); `task TT{n} restored {file}` (a `modified` verdict, put
   back from its blob); `batch {TT ids} reverted {file}` (`index` for the index).
4. `phase3 complete`.
5. `round N dispatched: {tasks}` — written **just before** the round's workers are spawned.
6. `## round N` — the round's verdict table, written after the full check. The initial check
   (no dispatch) is round 0.
7. `gate passed: {state}`, then `gate restored {file}` lines, then the `## gate recheck` table
   — Phase 3.5's recheck after the gate.
8. `run ended at {sha}: {Verification state}`, or `run ended at {sha}, commit due: {state}` on
   a green run — the last entry.

```markdown
# requirement-check — {spec name}
spec: sha256 {64 hex of spec.md}
head: {40 hex} on feat/projects-api

task T5 parked — Fenced: auth
task T1 done
task T3 done
phase3 complete

## round 0
| GWT | verdict | grounds | code | reason |
|-----|---------|---------|------|--------|
| R2.1 | met | test | ok | tests/tt2_projects_api_test.py::test_create_returns_201 passed |
| R2.3 | unmet | read | missing | src/api/projects.py:40 — no delete branch |
| R4.1 | out-of-scope | — | — | — |
unmet: 1 of 6 in scope (R2.3)
dispatched this round: (none)
blocked: (none)

round 1 dispatched: T3
task T3 blocked R2.3 — conflicts with the D4 payload format

## round 1
| GWT | verdict | grounds | code | reason |
...
unmet: 1 of 6 in scope (R2.3)
dispatched this round: T3
blocked: R2.3 — T3: conflicts with the D4 payload format

run ended at {40 hex of HEAD}: requirements unmet after 1 rounds
```

The footer lines carry the stop-condition inputs: the unmet total (compared with the previous
round over the same GWT set — a GWT that left scope between rounds is dropped from both
counts), the tasks the round re-dispatched, and every `BLOCKED` line workers returned. Round 1
above targets only `T3`: R2.3's code is `missing` on `read` grounds, and TT2 becomes a target
only on `does-not-exercise`, `wrong-expectation`, or `over-specifies`. After round 1 the only
unmet GWT is BLOCKED, so there is nothing left to target and the run ends. R4.1 is out of scope
because T5, the only task that fulfills R4, is parked. A `## gate recheck` table has the same
columns and footer, with `dispatched this round: (none)`.

**Run identity.** In both files the line right under the `#` heading is `spec: sha256 {hash}`,
measured with `shasum -a 256` when the file is created. Compare that line, never the heading.
The check and the resume rules that follow it are SKILL.md Phase 3.4 step 5.

## 3. TT worker prompt

One subagent per TT, regardless of pattern (in Sequential the orchestrator implements tasks
itself; the tests still come from a separate context). A TT batch runs with no other worker in
flight (SKILL.md TT-first step 1). Fill `{n}`, `{Rn}`, `{specPath}`.

Spawn with `capability:spawn-worker` (`../../references/runtime-tools.md`: the
`Agent` tool with the general-purpose type in Claude Code; `define_subagent` then
`invoke_subagent` under agy) and this prompt:

```
You are writing acceptance tests for requirement {Rn} of the spec at {specPath}. You did
not write the spec and you will not implement it; another worker does that after you.
Expected values come from the spec, never from running or reading the implementation.
It is normal for your tests to fail now.

1. Read `### {Rn}` and its sub-requirements. The heading ends with `— Dx, Dy`: those are
   the L2 decisions this requirement comes from. Read them under `## Decisions`. Copy
   their ids verbatim into your return; do not add or drop any.
2. Detect the test runner the way loop derives its Gate-1 commands: `package.json`
   scripts, `Makefile`, `pyproject.toml`, CI config. If none defines a test command,
   write no files and return every GWT as `manual: no test runner`.
3. For each sub-requirement:
   - Heading ends in `(manual)` → `manual: spec-marked`. No test.
   - Otherwise the When names the boundary the behaviour passes through: a route, a CLI
     command, a public function or module, or an event. Test only through that boundary,
     as a black box. Never guess internal module paths, signatures, or file layout. If
     the When names no such boundary → `manual: no spec-named boundary`. No test.
   - Assert the Then's observable outcome. You may also assert what the listed decisions
     fix (an API contract, payload shape, error string). Assert nothing beyond those: no
     exact wording the spec does not give, no extra fields, no ordering, no internal calls.
4. Files: create new test files only, in the directory this project keeps tests in. Each
   basename must start with `tt{n}_` AND match the pattern the project's test command
   collects by — its configured pattern, else the runner's default — so that one command
   picks the file up: `tt{n}_{topic}_test.py` for pytest (`*_test.py`),
   `tt{n}_{topic}.test.ts` for Jest / Vitest, `tt{n}_{topic}_test.go` for Go. If no name
   satisfies both (the configured pattern demands another prefix), write no files and
   return every GWT as `manual: collection pattern excludes the tt prefix`. Never edit,
   delete, or rename an existing file of any kind, and add no file without the prefix:
   put every fixture and helper inside your own `tt{n}_` files. List every file you
   create under `files:`; any other new file — a `conftest.py`, a fixture directory, an
   `__init__.py`, an unlisted test file, a cache your test run left — is removed. Run
   no git command that changes the index, a branch, or `HEAD`: leave your files
   untracked. Do not implement anything.
5. If this task needs a change to a database schema, a migration that can lose data,
   auth / permission / access control, payment, or security (secrets, crypto), do not
   make it. Stop and report `FENCED: {area} — {what you found}`.

Return exactly this shape:
TT{n} — {Rn} — L2: {ids copied from the heading}
run: {command that runs only your files} | none
{Rn}.1: test: {file}::{case} | manual: {reason}
{Rn}.2: ...
files:
- {path}
(or "files: none")
```

On a TTn re-dispatch (reason code `does-not-exercise`, `wrong-expectation`, or
`over-specifies`), the orchestrator has already removed the files the old block listed; it sends the same prompt with
the checker's lines for that Rn, from the last round table, appended under "Previous attempt —
the checker found:", so the tests are rewritten from the spec rather than patched.

## 4. Checker agent prompt

Modelled on specify's Spec Review: a fresh context that receives the inputs below and nothing
else — not the workers' reasoning, not the orchestrator's transcript. Its changed-file list is
every path in the orchestrator's `git status --porcelain -uall` — the tree, never the workers'
reports, which are claims. It reports; it fixes nothing. Checker failures — an error, a timeout,
a missing or duplicate line for an in-scope GWT, an `out-of-scope` verdict on an in-scope GWT,
grounds that contradict the mapping (`test` for a `manual:` GWT, `read` for a `test:` one), or a
verdict, grounds, and code that do not pair as the procedure below assigns them — are retried
once with a new context, then end the run as `requirements check failed`. A line that matches
neither shape is ignored, not fatal. A separator is `—`, `–`, or `-` / `--` with whitespace on
both sides, never a hyphen inside a token such as `does-not-exercise`; a line splits at its first
three separators only, so `{grounds}` may contain anything.

Spawn with `capability:spawn-inline-checker` (`../../references/runtime-tools.md`: the
`Agent` tool with the general-purpose type in Claude Code; `define_subagent` then
`invoke_subagent` under agy) and this prompt:

```
You are checking whether an implementation meets its spec's sub-requirements. You did not
write the spec, the tests, or the code. Judge only what the files and the test runs show.
Do not edit, create, or delete any file. Propose no fixes.

Inputs:
- spec: {specPath} — the sub-requirements under `## Requirements` (Given/When/Then);
  each `### Rn` heading ends with the L2 decision ids it comes from
- mapping: {specDir}/gwt-tests.md (or: no mapping — judge every GWT as read)
- changed files: {list}
- out of scope: {GWT ids}

For every sub-requirement in the spec, produce exactly one line:
1. Its id is in the out-of-scope list → `{id}: out-of-scope`. Do not judge it.
2. The mapping gives `test: {file}::{case}` → first run `shasum -a 256 {file}` and compare
   with the recorded hash; a file that no longer exists is a mismatch. A mismatch makes
   every GWT that file covers `unmet` with
   grounds `test` and code `modified`; the `{grounds}` field is the file and both hashes.
   Otherwise read the test and run the recorded command. Four criteria, checked in this
   order, each naming the code an `unmet` verdict gets:
   a. it calls the When's trigger through the boundary the When names (route, command,
      public function, event) — missing → `does-not-exercise`;
   b. it asserts the Then's observable outcome — missing → `does-not-exercise`;
   c. every value it expects is the one the Then or the listed decisions give (a status
      code, a field value, an error string) — judged against the spec text alone, never
      against what the code returns; an expectation the spec contradicts →
      `wrong-expectation`;
   d. its assertions stay within the Then plus the L2 decisions the mapping lists for
      that requirement — anything beyond → `over-specifies`. Confirm those ids appear
      in the `### Rn` heading; an id that does not is not part of the ceiling.
   A test that meets all four: passed → `met` with code `ok`, failed → `unmet` with code
   `test-fails`. The `{grounds}` field is `{file}::{case} passed`, or `{file}::{case}
   failed — {the failing assertion, one line}`; for `does-not-exercise`,
   `wrong-expectation`, and `over-specifies` it names what is missing, the expected value
   next to the one the spec gives, or what goes beyond the ceiling.
3. The mapping gives `manual: ...`, or has no entry for the id → read the changed files
   (and what they call) and judge `met` or `unmet` with `grounds: read`; the grounds are
   `file:line` references. Behaviour not present → `missing`. A missing entry is not an
   error on your side.

Return one line per sub-requirement, in spec order, and no other lines:
{id}: met | unmet — grounds: test|read — {code} — {grounds}
{id}: out-of-scope
`{code}` is exactly one of: ok | missing | test-fails | does-not-exercise |
wrong-expectation | over-specifies | modified. `met` is always `ok`, and `ok` always `met`;
`test-fails`, `does-not-exercise`, `wrong-expectation`, `over-specifies`, and `modified` go
with `grounds: test`; `missing`
goes with `grounds: read`. Every line carries all four fields,
`{grounds}` included, with the separators exactly as shown; a line with a field missing
is rejected. Full example of a `modified` line:
R2.1: unmet — grounds: test — modified — tests/tt2_projects_api_test.py recorded ab12…, now cd34…
```

The orchestrator's validation reads only lines of those two shapes (anything else is ignored),
checks each against the in-scope set, the mapping, and the verdict–code pairing as SKILL.md
Phase 3.4 step 2 lays out, and matches the code token, never the prose: `does-not-exercise |
wrong-expectation | over-specifies` make TTn the first re-dispatch target of the round, before
Rn's implementation tasks; `modified` restores the listed files from their blobs and targets
only the implementation tasks (SKILL.md Phase 3.4 step 3).

## 5. Re-dispatch worker prompt (common implementation-worker prompt)

In unattended mode every implementation worker — first dispatch or re-dispatch, any pattern —
gets this prompt. On a first dispatch the "Unmet" block and the keep-green line are omitted;
everything else is identical, so the orchestrator can rely on `BLOCKED` lines from round 0.
A re-dispatched task always goes to a **new** worker of the same role; the original DAG
rules (`Depends on`, file overlap) decide order and parallelism among the targets.

Spawn with `capability:spawn-worker` (`../../references/runtime-tools.md`: the
`Agent` tool with the general-purpose type in Claude Code; `define_subagent` then
`invoke_subagent` under agy) and this prompt:

```
Implement the task below from the spec at {specPath}. Read the requirements it fulfills
directly; their Given/When/Then are the acceptance criteria.

Task:
{the task's `### Tn` block, verbatim}

Unmet after the last check — fix these:
{one line per GWT, as the checker returned it, e.g.
 R2.3: unmet — grounds: read — missing — src/api/projects.py:40 — no delete branch}
Keep every GWT already judged met green; the recheck covers all of them, not only these.

Do not modify any test file listed in {specDir}/gwt-tests.md. Those tests are the check;
if one looks wrong, say so in your report and leave it.

Run no git command that changes the index, a branch, or HEAD (no `git add`, `git commit`,
or `git stash`). The run commits once, at the end, and only if every check passes.

If this task needs a change to a database schema, a migration that can lose data,
auth / permission / access control, payment, or security (secrets, crypto), do not
make it. Stop and report `FENCED: {area} — {what you found}`.

If a GWT cannot be met without changing the spec or a decision, do not work around it.
Report it as `BLOCKED: {GWT id} — {reason}` and continue with the others.

Report: the files you changed, and every `FENCED:` or `BLOCKED:` line.
```

A `BLOCKED` GWT is still judged by the checker every round, and a `met` verdict counts as met.
Its effect on targeting is GWT-scoped and lasts for the rest of the run: no task is
re-dispatched for that GWT — not the task that reported it, and not another task that fulfills
the same requirement — because the block is between the GWT and the spec, not between the GWT
and one task. A task stays a target for the requirement's *other* unmet GWTs, and the "Unmet"
block it receives omits the BLOCKED ones. The reason goes into the ledger and the report. This
is the same rule SKILL.md Phase 3.4 step 3 states.
