---
name: loop
argument-hint: "[task or goal]"
description: |
  Run a task as a supervised verification loop instead of a one-shot prompt.
  Establishes a loop contract (3 gates: Pass/Fail, Quantitative, Qualitative),
  then iterates Work → Verify → Fix until every gate passes — emitting an
  objective evidence report before declaring done. Stops and escalates to a
  human when an autonomy boundary is crossed (schema change, data-loss
  migration, auth/payment/security, or a change that conflicts with the spec).
  Implements the "Ralph loop" technique — the iterative-refinement pattern that
  agent-orchestrate selects as its Loop pattern.
  Use when: "/loop", "loop", "run until it passes", "iterate until tests pass",
  "supervise this until done", "loop.md", "verification loop", "ralph loop",
  "don't stop until the gates pass", "keep going until criteria met".
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - AskUserQuestion
  - Agent
  - PushNotification
---

# /loop — Supervised Verification Loop

Run a task as a **loop**, not a prompt.

A prompt says "do X" once and trusts the reply. A loop says "do X, then prove it
passes the gates; if it doesn't, fix it and re-verify — repeat until the gates
pass or you hit a boundary that requires a human." You stop being the remote
control issuing "fix this / change that" and become the **supervisor** who
defined what "done" means up front.

The model marks its own homework generously, so this skill never trusts a bare
"done." It forces an **evidence report** — gate results, numbers, and, for every
subjective judgement, a score *plus objective grounds plus a corrective action*.

---

## The Loop Contract (`loop.md`)

Every loop runs against a contract with three gate types. Before any work
starts, this contract must exist and be approved.

| Gate | Question | Rule |
|------|----------|------|
| **1. Pass/Fail** | Does it build / typecheck / lint / test? | **100% required.** Binary. One failure = not done. |
| **2. Quantitative** | Do the numbers clear the thresholds? | Each metric has a stated threshold. Below threshold = not done. |
| **3. Qualitative** | Is the design/flow actually good? | Score **+ objective grounds + corrective action**. A bare high score is rejected. |

### Gate 1 — Pass/Fail (binary, 100%)
Concrete commands whose exit code decides the gate. Typical members:
build succeeds, type check clean, linter clean, test suite green.
If a command does not exist for this project, say so — do not silently skip it.

### Gate 2 — Quantitative (numbers vs thresholds)
Measured values, each with a threshold agreed in the contract. Examples:
test coverage ≥ N%, p95 latency ≤ N ms, error-log rate ≤ N, bundle size ≤ N.
Report the measured number next to its threshold every iteration.

### Gate 3 — Qualitative (judged, with evidence)
Things that need judgement: architecture fit, naming clarity, naturalness of the
user flow, spec alignment. **The model inflates its own scores**, so each
qualitative item MUST be written as:

```
<item>: <score>/10
  grounds: <specific, checkable observation — file/line, a measured fact, a comparison>
  action: <the concrete change that would raise it, or "none — meets bar"
           and why no change is needed>
```

A score with no grounds and no action is invalid and the gate fails.

---

## Autonomy Boundary

Inside the loop the model fixes things on its own. But unbounded autonomy lets it
"improve" its way into wrecking the design or doing something irreversible. So the
loop has a hard fence.

### ✅ Auto-fix (stay in the loop, no asking)
- Lint / formatting / type errors
- Adding missing tests for code already in scope
- Documentation and comment updates
- Local renames / naming clean-ups
- Refactors with no behaviour change that keep all Gate-1 commands green

### 🛑 STOP and call the human (escalate, do not proceed)
- **Database schema changes**
- **Migrations that can lose data** (drops, destructive backfills, irreversible transforms)
- **Auth / permission / access-control policy changes**
- **Payment or security-sensitive changes** (secrets, crypto, billing)
- **Anything that conflicts with the approved spec / PRD / original intent**
- Deleting or overwriting work you did not create, when what you find contradicts the task

When a boundary is hit: stop the loop, write what you found, why it crossed the
fence, and the options — then ask via AskUserQuestion. Never push through it.

---

## Self-Learning Lessons (`## Lessons` in `loop.md`)

A loop should not repeat a mistake it already made. Every escalation or gate
failure is a candidate **lesson** that gets written into the contract's
`## Lessons` section and replayed on the next run — so each past failure becomes a
permanent check the loop can't trip over again.

**Record shape** (skeleton in `references/loop-template.md`):

```
### <id> — <short title>
- cause: escalation | gate-fail
- source: human-approved | auto-unattended
- form: gate1-command | gate3-item | context
- status: active | needs-review | retired
- check: <hardened Gate-1 command | Gate-3 item text | "—" for context>
- note: <what went wrong, what this prevents — one line>
```

**Harden once, at record time.** When a lesson is recorded (Phase 5), decide its
`form` ONCE and store it. Prefer a deterministic check over a memo (the model
ignores memos): turn the lesson into a runnable **Gate-1 command** when possible,
else a **Gate-3 item**, and fall back to **context** only when neither fits. A
hardened Gate-1 command must be real and runnable — never a placeholder. Phase 0
then just *loads* the stored form; it never re-hardens on later runs.

**Scope.** Lessons live in THIS `loop.md` and apply only to this contract. They do
not propagate to other contracts/features — a deliberate trade-off (global
propagation is out of scope).

**Lifecycle.**
- `active` → loaded as a live gate / guidance by Phase 0.
- `needs-review` → a hardened check that now fails for an *environmental* reason
  (missing tool/file, not a real regression). Mark it `needs-review` and surface
  it — never auto-delete, and don't let it wedge the gate. Only a human moves it
  back to `active` (after fixing) or to `retired`.
- `retired` → kept for history, not loaded.
Promoting a `context` lesson to a hardened form is a **human edit only** — no
auto-promotion.

**De-dup.** The key is the normalised `cause` + `check`. A candidate whose key
already exists is not added again — this keeps `## Lessons` from bloating with
noise. Curation owner = the human (see Phase 5).

---

## Phase 0 — Establish the Contract

1. **Find or build `loop.md`.** Look for an existing `loop.md` (repo root, the
   spec/feature dir, or a path the user named). If one exists, read it and use
   its gates. If not, derive a draft from the task + project:
   - Detect Gate-1 commands from the project (e.g. `package.json` scripts,
     `Makefile`, `pyproject.toml`, CI config). Use `references/loop-template.md`
     as the skeleton.
   - Propose Gate-2 thresholds and Gate-3 items relevant to the task.
2. **Load prior lessons (self-learning).** If `loop.md` has a `## Lessons`
   section, fold every `status: active` lesson into the contract by its `form`:
   - `gate1-command` → add its `check` as a Gate-1 command.
   - `gate3-item` → add its `check` as a Gate-3 qualitative item.
   - `context` → carry its `note` as guidance the work must honour (no gate).
   `needs-review` and `retired` lessons are shown but NOT activated. Do not
   re-harden — load the stored `form` as-is. Pull lessons only from THIS
   `loop.md`, never from other contracts.
3. **Get approval.** Present the drafted contract (including any active lessons
   now folded in) and confirm via AskUserQuestion before running the loop. The
   user owns the bar; you don't get to lower it later. Write the approved
   contract to `loop.md` — and when you (re)write it, **preserve the existing
   `## Lessons` section verbatim**; never overwrite or drop it.

If the task is trivial and the user just wants it run, you may present a minimal
contract (Gate 1 only) and proceed on approval — but always state the gates.

---

## Phase 1 → 3 — The Loop

Repeat until **exit** (all gates pass) or **escalate** (boundary hit):

```
Phase 1  WORK
  Do the next increment of the task.
  Stay strictly inside the Auto-fix list. The moment the work requires
  something on the STOP list → jump to ESCALATE.

Phase 2  VERIFY  (run the gates, top to bottom)
  Gate 1: run each Pass/Fail command, record exit status.       (maker runs)
  Gate 2: measure each metric, record value vs threshold.       (maker runs)
  Gate 3: a SEPARATE checker subagent scores each item           (maker ≠ checker)
          with grounds + action — see "Gate 3 — maker ≠ checker".

Phase 3  DECIDE
  IF every gate passes        → EXIT  → emit Evidence Report (done)
  ELIF the fix is Auto-fix    → apply it, loop back to Phase 1
  ELIF boundary hit           → ESCALATE (stop, ask the human)
  ELSE (can't fix within bounds, or no progress two iterations running)
                              → ESCALATE with the blocker
```

**Anti-spin rule:** if an iteration makes no gate go from fail→pass, do not loop
again blindly — report the stuck gate and escalate. Loops fix; they don't thrash.

**Stale-lesson rule:** if a Gate-1 command that came from a `## Lessons` entry
fails because it *can't run* (missing tool/file) rather than on substance, treat
it as environmentally stale — mark that lesson `needs-review`, surface it, and do
not let it wedge the gate. Never auto-delete a lesson.

---

## Gate 3 — maker ≠ checker

Gate 1 and Gate 2 are deterministic (a compiler / test / metric gives the same
answer no matter who runs them), so the maker runs them itself. **Gate 3 is a
judgement, and the model inflates scores on its own work** — so the maker must not
be the one who scores it. A separate **checker subagent** evaluates Gate 3.

**How (when the `Agent` tool is available):**
1. Spawn a checker via `Agent`. Give it ONLY: the diff under review, the `loop.md`
   contract, the spec/PRD file if `loop.md`'s Goal references one, and the list of
   changed file paths. Do **not** hand it the maker's reasoning — the separation is
   the whole point.
2. The checker returns each Gate-3 item as `score/10 + grounds + action` (the same
   format the contract requires; a bare score is invalid).
3. **Split scoring.** Some Gate-3 items (e.g. deep "architecture fit") need
   whole-codebase knowledge the checker wasn't given. Score only the items the
   checker *can* ground from the diff/spec as **checker-scored**; mark the rest
   `self-graded` (the maker scores them, openly flagged). Inflation is blocked on
   the checker-scored items, and the self-graded ones are at least honest about
   being unverified.

**Fallback (no `Agent` tool in this environment):** the maker self-grades every
Gate-3 item and the whole gate is labelled `unverified` in the Evidence Report.
Never silently pass an unverified Gate 3.

Gate 1 and Gate 2 stay maker-run, unchanged.

---

## Phase 4 — Evidence Report

A loop never ends with "done." It ends with proof. Emit:

```markdown
## Loop Report — <task>

**Verdict:** ✅ all gates passed  |  🛑 escalated: <reason>
**Iterations:** <n>

### Gate 1 — Pass/Fail
- build: ✅ / ❌   (command)
- typecheck: ✅ / ❌
- lint: ✅ / ❌
- tests: ✅ / ❌  (<passed>/<total>)

### Gate 2 — Quantitative
| metric | measured | threshold | ok? |
|--------|----------|-----------|-----|
| ...    | ...      | ...       | ✅/❌ |

### Gate 3 — Qualitative   (checker-scored via separate subagent; `unverified` if no Agent tool)
- <item>: <score>/10 [checker-scored | self-graded] — grounds: <...> — action: <... | none>

### Boundary log
- <any STOP-list item encountered and how it was handled>
```

If escalating, the report ends at the boundary with the question for the human —
do not fabricate passing gates to close the loop.

---

## Phase 5 — Compound (record lessons)

A loop that forgets its failures repeats them. After Phase 4, whenever this run
**escalated** or hit a **gate failure** along the way, turn the cause into one or
more candidate lessons and fold them back into the contract so the next run can't
trip the same way.

1. **Draft candidates.** For each escalation / gate-fail, draft a lesson record
   (shape in "Self-Learning Lessons"). Decide `form` now — harden to a Gate-1
   command if possible, else a Gate-3 item, else context. Drop any candidate
   whose normalised `cause`+`check` already exists in `## Lessons` (de-dup).
2. **Curate by mode:**
   - **Interactive (default):** present the candidates and let the human choose
     which to keep. Append only the approved ones, tagged `source: human-approved`.
     The human owns `## Lessons` — never auto-write in this mode.
   - **Unattended:** ONLY when the invocation carries an explicit `mode: unattended`
     marker (set by the `/loop` automation wrapper — see Automation). With no human
     to approve, append the candidates automatically, tagged `source: auto-unattended`,
     so the lesson still compounds; the tag lets a human review/prune them later.
   - **No marker = no auto-append.** A self-paced re-run in an interactive session
     *without* the marker stays on the Interactive path — it never auto-writes.
3. **Write.** Append the kept lessons to the `## Lessons` section of `loop.md`
   (preserving everything already there). Each new lesson starts at `status: active`.

Recording a lesson is the only thing that makes the loop *compound*. Skipping it
on a real failure means the loop pays for that mistake again next run.

---

## Automation (optional heartbeat)

The loop is normally driven turn-by-turn by a human. For a contract whose
`loop.md` is already approved, you can also run it on a **schedule** — a heartbeat
that re-runs Work → Verify → Fix unattended until the gates pass or it escalates.

**Entry point (one way):** schedule the loop with the built-in interval command:

```
/loop <interval> /harness-ops:loop <task or spec path> mode: unattended
```

`/loop <interval>` is the recurring runner; `mode: unattended` is the marker that
Phase 5 keys on. Nothing new is built — automation is just this command plus the
rules below. (No always-on daemon; stop it the way you'd stop any `/loop`.)

**On escalation, surface — don't push through.** When an unattended tick hits a
🛑 STOP boundary, makes no fail→pass progress, or otherwise escalates: stop the
tick and notify a human via **`PushNotification`**. If `PushNotification` isn't
available in the environment, append the escalation reason to
`<specDir>/loop-escalation.md` for the human to find next session. Either way the
tick ends there — it does not push through the fence.

**Hard limits (unchanged by automation):**
- The autonomy fence still holds — STOP-list items escalate, never auto-proceed.
- **No auto-merge.** Automation never merges and never bypasses `block-main-push`
  or any other gate. The merge stays with the human.
- Unattended lesson recording follows Phase 5's `auto-unattended` path (auto-append
  + tag) so a human can review/prune later.

---

## Rules

1. **Contract before work** — no loop without approved gates. Never lower the bar mid-loop.
2. **No bare "done"** — every exit carries an evidence report with numbers and grounds.
3. **Qualitative needs grounds + action** — a lone score fails the gate.
4. **The fence is hard** — STOP-list items escalate to a human, always. No exceptions to "just this once."
5. **Loops fix, not thrash** — no fail→pass progress means escalate, not re-run.
6. **`loop.md` is the source of truth** — persist the approved contract so the loop is resumable and auditable.
7. **Maker ≠ checker on Gate 3** — the maker never scores its own Gate 3; a separate checker subagent does, or it's flagged `unverified`. Gate 1·2 stay maker-run.
8. **New capabilities are opt-in and additive** — Lessons activate only when `## Lessons` exists; auto-recording only under the `mode: unattended` marker; automation only via `/loop`. The invocation interface (args) is unchanged, so existing callers — including agent-orchestrate's Ralph Loop pattern and its Phase 3.5 verification gate — keep working unmodified. A bare contract with no marker behaves exactly as before; the one always-on change is that Gate 3 is checker-scored when the `Agent` tool is available.
