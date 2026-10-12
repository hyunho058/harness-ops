# Requirement Check — formats and prompt templates

Used by `skills/agent-orchestrate/SKILL.md` › `## Unattended Mode` (Phase 3 "run TT tasks first",
Phase 3.4 "Requirement Check", and the re-dispatch rounds). Interactive runs never read this
file. Everything here is written or read by the orchestrator; workers and the checker only
receive the prompts below and return text.

**Identification.** A TT task is one whose id matches `TT\d+` (equivalently, whose `Fulfills`
contains `(tests)`). Every other task, including `[infra]`, is an implementation task. Signal
exclusion, TT-first execution, park non-propagation, and re-dispatch targeting all use this key.

**File cleanup for a failed, fenced, or re-dispatched TT.** The orchestrator takes
`git status --porcelain -uall` before and after each TT; the TT's files are the new entries in
that diff whose basename starts with `tt{n}_`. On resume there is no "before" snapshot, so
before re-running a TT that has no `gwt-tests.md` block, every untracked (`??`) file whose
basename starts with `tt{n}_` is treated as that TT's and removed. The prefix keeps a parallel
sibling's files safe; `-uall` keeps a new test directory from collapsing into one `?? tests/`
line that would never match a basename. Before a TTn re-dispatch, remove the files listed in
its block instead — the block is the record for a TT that finished.

## 1. `gwt-tests.md` — GWT to test mapping

Path: `{specDir}/gwt-tests.md`. **The orchestrator is the single writer.** TT workers return
text (section 3) and never touch this file; parallel TTs writing one file would lose updates.
The orchestrator creates the file with the `spec:` line (run identity, §2) and the R0 block, then
appends one block each time a TT finishes — so on resume a TT that already has a block is not
re-run, and one without a block is.

Hashes are **measured by the orchestrator** with `shasum -a 256` on each file in the TT's
returned list, at the moment the block is written and again after a TTn re-dispatch (the old
block is replaced). A TT never returns hashes: a 64-character hex string from an LLM worker is
a claim, not evidence ("A claim in the args is not evidence; read the file" — SKILL.md,
Unattended Mode).

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
  - tests/tt2_projects_api_test.py  sha256: {64 hex}

## TT3 — R3 — L2: D5
- run: none
- R3.1: manual: no test runner
- files: none
```

Each block: the TT id, its Rn, the L2 ids the TT copied from the `### Rn` heading; one `run:`
line (`none` when every GWT is manual); one line per sub-requirement, `test: {file}::{case}`
or `manual: {reason}`; the file list with one hash per file. Statuses only the orchestrator
writes: `manual: goal-level` (R0 has no TT, so no return value), `manual: TT failed — {reason}`
and `manual: TT fenced — {reason}` (the TT errored, timed out, or reported FENCED — a block
with no run line and no files; Rn's implementation tasks still run), and `manual: parked`
(every implementation task of Rn became parked after the TT ran; the TT's files are removed
at the same time and those GWTs leave the check scope).

## 2. `requirement-check.md` — round ledger

Path: `{specDir}/requirement-check.md`. Three kinds of entry, all written by the orchestrator,
each by **atomic write**: write the whole new content to `{specDir}/requirement-check.md.tmp`,
then rename over the target. The file is the resume state for the check loop (the counterpart
of loop's `progress.md`); `specs/` is gitignored, so it is never committed.

1. `spec: sha256 {hash of spec.md}` and `phase3 complete` — the first two lines, written
   together the moment Phase 3 execution ends; this is what creates the file. The hash is the
   run identity (below).
2. `round N dispatched: {tasks}` — written **just before** the round's workers are spawned,
   never after. Without it, a compaction between dispatch and recheck restores N to the
   previous value and the same task is sent a third time.
3. The round's verdict table — written at round end, after the full recheck. The initial
   check (no dispatch) is round 0.

```markdown
# requirement-check — {spec name}
spec: sha256 {64 hex of spec.md}

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

## round 1
| GWT | verdict | grounds | code | reason |
...
unmet: 1 of 6 in scope (R2.3)
dispatched this round: T3
blocked: R2.3 — T3: conflicts with the D4 payload format
```

The footer lines carry the stop-condition inputs: the unmet total (compared with the previous
round over the same GWT set — a GWT that left scope between rounds is dropped from both
counts), the tasks the round re-dispatched, and every `BLOCKED` line workers returned. Round 1
above targets only `T3`: R2.3's code is `missing` on `read` grounds, and TT2 becomes a target
only on `does-not-exercise`, `over-specifies`, or `modified` (SKILL.md Phase 3.4 step 3).

**Run identity.** Both files open with `spec: sha256 {hash}` — the `shasum -a 256` of `spec.md`,
measured by the orchestrator when it creates the file (the counterpart of loop's `contract_ref`).
Whenever either file is read — at the start of a run or on resume — recompute the hash first. A
mismatch means the files belong to an earlier run on a different spec, not to this one: remove
the test files the stale `gwt-tests.md` lists, delete both files, and start Phase 3 from the
beginning. Without this line a re-invocation on an edited spec would read the old ledger as a
resume, skip Phase 3, and end again with the old verdict. Matching hashes make the files this
run's and the resume rules below apply — so a re-invocation on an *unchanged* spec continues
where the earlier run stopped, and one whose last table already ended the run ends again the
same way. To start over on an unchanged spec, remove the two files; the report's next step says
so when a run ends unmet.

**Resume rules** (after compaction, and after the run-identity check, read this file first):
- No file, or no `phase3 complete` line → Phase 3 is still running. Resume Phase 3 as before
  (re-run TTs without a `gwt-tests.md` block, then the remaining tasks) and run no check.
- `phase3 complete` and nothing after it → round 0: run a full recheck.
- The last entry is a `round N dispatched` line with no `## round N` table after it → the
  round's workers may or may not have finished; the working tree is the truth. Run a full
  recheck and count its result as the end of round N (it decides the stop condition exactly as
  a normal round end would).
- The last entry is a `## round N` table (round 0's included) → that round's check already ran
  on this tree. Do **not** recheck: evaluate the exit conditions from the table — its unmet
  total against the previous table's — and either write `round N+1 dispatched` and dispatch,
  or end. A second check here would compare the tree with itself, find no decrease, and end
  the run while rounds were still allowed.
- Never resume a worker; a half-finished re-dispatch is simply what the recheck sees.

## 3. TT worker prompt

One `Agent` per TT, regardless of pattern (in Sequential the orchestrator implements tasks
itself; the tests still come from a separate context). Fill `{n}`, `{Rn}`, `{specPath}`.

```
Agent(subagent_type="general-purpose", prompt="""
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
   return every GWT as `manual: collection pattern excludes the tt prefix`. Never edit an
   existing test file or any other file. Do not implement anything.
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
""")
```

On a TTn re-dispatch (reason code `does-not-exercise`, `over-specifies`, or `modified`), the
orchestrator has already removed the old files; it sends the same prompt with the checker's
lines for that Rn appended under "Previous attempt — the checker found:", so the tests are
rewritten from the spec rather than patched.

## 4. Checker agent prompt

Modelled on specify's Spec Review: a fresh context that receives the inputs below and nothing
else — not the workers' reasoning, not the orchestrator's transcript. Its changed-file list is
every path in the orchestrator's `git status --porcelain -uall` — the tree, never the workers'
reports, which are claims. It reports; it fixes nothing. Checker failures (error, timeout, a line of any other shape, a missing in-scope line)
are retried once with a new context, then end the run as `requirements check failed`.

```
Agent(subagent_type="general-purpose", prompt="""
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
   with the recorded hash. A mismatch makes every GWT that file covers `unmet` with
   grounds `test` and code `modified`; the `{grounds}` field is the file and both hashes.
   Otherwise read the test and run the recorded command. Three criteria, checked in this
   order, each naming the code an `unmet` verdict gets:
   a. it calls the When's trigger through the boundary the When names (route, command,
      public function, event) — missing → `does-not-exercise`;
   b. it asserts the Then's observable outcome — missing → `does-not-exercise`;
   c. its assertions stay within the Then plus the L2 decisions the mapping lists for
      that requirement — anything beyond → `over-specifies`. Confirm those ids appear
      in the `### Rn` heading; an id that does not is not part of the ceiling.
   A test that meets all three: passed → `met` with code `ok`, failed → `unmet` with code
   `test-fails`. The `{grounds}` field is `{file}::{case} passed`, or `{file}::{case}
   failed — {the failing assertion, one line}`; for `does-not-exercise` and
   `over-specifies` it names what is missing or what goes beyond the ceiling.
3. The mapping gives `manual: ...`, or has no entry for the id → read the changed files
   (and what they call) and judge `met` or `unmet` with `grounds: read`; the grounds are
   `file:line` references. Behaviour not present → `missing`. A missing entry is not an
   error on your side.

Return one line per sub-requirement, in spec order, and no other lines:
{id}: met | unmet — grounds: test|read — {code} — {grounds}
{id}: out-of-scope
`{code}` is exactly one of: ok | missing | test-fails | does-not-exercise |
over-specifies | modified. `met` is always `ok`. Every line carries all four fields,
`{grounds}` included, with the separators exactly as shown; a line with a field missing
is rejected. Full example of a `modified` line:
R2.1: unmet — grounds: test — modified — tests/tt2_projects_api_test.py recorded ab12…, now cd34…
""")
```

The orchestrator's format check accepts only those two shapes and matches the code token,
never the prose: `does-not-exercise | over-specifies | modified` make TTn the first
re-dispatch target of the round, before Rn's implementation tasks.

## 5. Re-dispatch worker prompt (common implementation-worker prompt)

In unattended mode every implementation worker — first dispatch or re-dispatch, any pattern —
gets this prompt. On a first dispatch the "Unmet" block and the keep-green line are omitted;
everything else is identical, so the orchestrator can rely on `BLOCKED` lines from round 0.
A re-dispatched task always goes to a **new** worker of the same role; the original DAG
rules (`Depends on`, file overlap) decide order and parallelism among the targets.

```
Agent(subagent_type="general-purpose", prompt="""
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

If this task needs a change to a database schema, a migration that can lose data,
auth / permission / access control, payment, or security (secrets, crypto), do not
make it. Stop and report `FENCED: {area} — {what you found}`.

If a GWT cannot be met without changing the spec or a decision, do not work around it.
Report it as `BLOCKED: {GWT id} — {reason}` and continue with the others.

Report: the files you changed, and every `FENCED:` or `BLOCKED:` line.
""")
```

A `BLOCKED` GWT is still judged by the checker every round, and a `met` verdict counts as met.
Its effect on targeting is GWT-scoped and lasts for the rest of the run: no task is
re-dispatched for that GWT — not the task that reported it, and not another task that fulfills
the same requirement — because the block is between the GWT and the spec, not between the GWT
and one task. A task stays a target for the requirement's *other* unmet GWTs, and the "Unmet"
block it receives omits the BLOCKED ones. The reason goes into the ledger and the report. This
is the same rule SKILL.md Phase 3.4 step 3 states.
