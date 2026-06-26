---
name: build-order
argument-hint: "[specs glob or manifest path | resume]"
description: |
  Orchestrate MANY feature specs through the harness-ops:loop skill as one
  unattended, resumable "build order". Generates a topologically-ordered
  build_order.md ledger from a set of feature specs, then drives each ready feature
  through /loop one at a time — advancing on a green exit and PARKING (while
  continuing independent features) on an escalation. The durable build_order.md
  ledger makes the whole multi-feature run resumable across context compaction: it
  is the OUTER analogue of loop's progress.md. Reuses the loop skill for ALL gating
  and verification — it never reimplements gates, maker≠checker, or lessons.
  Use when: "/build-order", "build order", "build all the specs", "run the specs
  overnight", "orchestrate multiple features", "unattended multi-feature build",
  "build_order.md", "drive these specs through the loop", "park and continue".
  Do NOT trigger for: a single feature/spec (use /harness-ops:loop directly), or
  choosing an execution pattern for one task (use /agent-orchestrate).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - AskUserQuestion
  - Skill
  - PushNotification
---

# /build-order — Multi-Feature Build Orchestrator

Drive **many** feature specs to "done" through the loop, unattended, resumably.

`/loop` supervises **one** feature against one gate contract. `build-order` is the layer
**above** it: it plans an ordered set of features, then hands each one to `/loop` in turn. It
owns *sequencing and bookkeeping* — never verification. Every gate, every maker≠checker check,
every lesson stays inside the loop skill; `build-order` only decides **what runs next** and
**records what happened**.

The point is an **overnight** run: approve a plan once, then let it grind through feature after
feature while you sleep — surviving the context compactions that a multi-hour run inevitably hits.

---

## The three-layer ledger

```
build_order.md   ← cross-feature ledger   (this skill owns)   "which features, in what order, done/parked?"
   ⊃ loop.md     ← per-feature contract    (loop owns)         "what does THIS feature's done mean?"
      ⊃ progress.md ← within-feature state (loop ① owns)       "where in THIS feature's loop are we?"
```

Each layer is durable and resumable on its own:
- `progress.md` (component ①) resumes the **inner** loop across a compact.
- `build_order.md` (this skill) resumes the **outer** orchestration across a compact — it records
  which feature is `done` / `in-progress` / `parked`, so a compacted overnight run re-reads it
  instead of re-planning.

`build-order` never duplicates a lower layer's state. It records only **which feature** is current;
*where* inside that feature is the loop's `progress.md`.

---

## build_order.md — the ledger

A durable Markdown file (written **atomically** — temp + rename — so a compact/crash can't tear it).
It is the orchestrator's **source of truth**; state never lives in ephemeral `TaskCreate`.

**Location.** Repo root by default, or a directory named at invocation (e.g. a `<buildDir>`),
beside the `specs/` it orchestrates.

**Shape:**

```
# build_order.md — <project / batch name>
- generated_at: <when>            # stamp, set by the caller
- input_ref: <fingerprint of the input spec set>   # for reconcile (see Resume)

## Features  (topological order)
### <feature-id>
- spec: <path to that feature's spec.md>
- depends_on: [<feature-id>, ...]   # edges; empty = a root
- status: pending | in-progress | done | parked
- reason: escalated | no-spec | error          # only when status = parked
- accept: <one-line acceptance seed for this feature>
```

**Status semantics:**
- `pending` — planned, not yet started.
- `in-progress` — its `/loop` is currently driving (written **atomically before** the loop call).
- `done` — its `/loop` exited green.
- `parked` — stopped needing a human; `reason` says why (`escalated` boundary / `no-spec` /
  `error` from the loop invocation itself). **Parked is sticky** — only a human flips it back to
  `pending`.

**`blocked` is NOT a stored status.** A feature is *blocked* when a `depends_on` is unmet or
transitively `parked`; that is **computed from the graph each cycle**, never written to the ledger
(so it can't go stale). The **ready set** = features that are `pending` AND every `depends_on` is
`done`.

---

## Phase 1 — Plan

Turn a set of feature specs into an approved, ordered `build_order.md`. Runs once at the start of a
batch (and is the thing a resume reconciles against — see Phase 4).

### 1. Resolve the input spec set
- **Explicit** — a manifest / list of features (with their `depends_on`) passed at invocation, OR
- **Glob fallback** — when none is given, discover specs by glob (e.g. `specs/*/spec.md`). Derive
  each feature's `depends_on` from its spec metadata if present, else treat it as a root.

### 2. Build the dependency graph + topological order
- Order features so every `depends_on` precedes its dependents.
- **Cycle → refuse to start.** If the graph has a cycle (topological sort fails), do **not** write or
  approve a `build_order.md`; report the cycle (the offending edges) and stop. A planning error is
  surfaced before any unattended run, never silently dropped.

### 3. Classify each feature
- Spec exists and parses → `status: pending`.
- **No `spec.md`** for a listed feature → `status: parked, reason: no-spec`, and surface it. Spec
  *generation* is `/specify`'s job, not this skill's — keep the separation.
- A **referenced spec that does not parse** → treat as a plan-time error (Phase-1 refuse, step 2's
  spirit): report it rather than guessing.
- **Already-built features** (brownfield): default to `pending` — do NOT guess "done" from a file's
  existence or name. Two things handle it: (a) the human may pre-mark a feature `status: done` at
  Approve (Phase 2) to skip it entirely; (b) either way the Drive phase invokes loop **verify-first**,
  so an already-satisfied feature passes its gates immediately and is recorded `done` with no rework.
  **The gates are the only "done" signal.**

### 4. Write build_order.md (atomically)
- Render the ledger (see "build_order.md — the ledger") using `references/build_order-template.md`
  as the skeleton: features in topological order, each `pending` (or `parked: no-spec`), with
  `spec`, `depends_on`, `accept`, and an `input_ref` fingerprint of the whole input set (Goal lines
  + spec paths) for later reconcile.
- Write via **temp file + rename** so a crash mid-write can't leave a torn ledger.

The plan is now drafted but **not yet runnable** — it must be approved (Phase 2) before any work.

---

## Phase 2 — Approve (plan + every feature's gate contract, in one batch)

An unattended run must never start on an unapproved plan. And because each feature's `/loop` would
otherwise stop to ask a human to approve *its own* `loop.md` contract (loop's Phase 0), those
per-feature approvals are collected **here, up front, in one batch** — so the overnight run never
blocks on a human mid-stream.

### 1. Draft each feature's gate contract
For every non-parked feature, draft a `loop.md` **from its spec**, using loop's contract template
(`${CLAUDE_PLUGIN_ROOT}/skills/loop/references/loop-template.md` — it lives in the *loop* skill, not
here) as the skeleton (detect Gate-1 commands from the project; seed Gate-2 thresholds and Gate-3
items from the spec's Requirements / `accept`). This only **prepares** the
contract for the human to approve — the gates are still *run and enforced by the loop skill*, never
here. (That is the R7.2 line: `build-order` prepares and sequences; loop verifies.)

### 2. Present for one-batch human approval (AskUserQuestion)
Show the human, together:
- the `build_order.md` plan — features, topological order, `depends_on`, and any `parked: no-spec`;
- each feature's drafted `loop.md` gates.

Ask for a single approval covering the whole plan **and** all the gate contracts. The human owns
the bar — for the whole batch, up front.

**Pre-mark already-built features `done` (optional optimization).** On a brownfield project the human
may flip features that are already complete to `status: done` here, so they are skipped entirely (no
verify tick spent). This is an *optimization, not a safety requirement*: any feature left `pending`
that is in fact already done will still verify-green on its first Drive pass (verify-first) and be
recorded `done` with no rework. Never auto-mark `done` from a guess — only an explicit human flip, or a
passed gate, sets `done`.

### 3. On approval
- Write each approved `loop.md` into its feature's spec directory (so the loop finds an
  already-approved contract there).
- Mark `build_order.md` approved (record `generated_at` / approver).
- This batch approval **is** the pre-approval that Phase 3 passes to each `/loop` via the
  `mode: unattended` marker: loop's Phase 0 then sees an approved `loop.md` + that marker and
  **skips its own `AskUserQuestion`** (R6) — while still running every gate.

### 4. No approval → no unattended run
Without this approval, `build-order` does not start an unattended run (R2.1). (It may still drive a
single feature **interactively**, where loop asks for that feature's contract approval the normal way
— no loop bypass needed.)

---

## Phase 3 — Drive

The core cycle. `build-order` **never verifies anything** here — it picks the next feature, hands it
to `/loop`, reads what the loop left behind, records it, and moves on.

### The cycle

```
loop:
  ready = features that are `pending` AND every depends_on is `done`   # computed fresh each pass
  IF ready is empty:
     IF every feature is `done`            → FINISH (all done)
     ELSE (unfinished remain, all blocked) → DEADLOCK  (see below)
  feature = pick ONE from ready, deterministically: topological order, then build_order.md
            declared order  (so a resumed run picks the same "current" feature)
  set feature.status = in-progress   and FLUSH build_order.md atomically  # BEFORE the loop call
  outcome = drive(feature)                                                 # invoke /loop, read signals
  record(outcome); FLUSH build_order.md atomically
  # back to the top — one feature at a time (sequential)
```

### drive(feature) — delegate to the loop, read the verdict from files

1. **Invoke the loop, never the gates — verify-first.** Call
   `Skill(skill="harness-ops:loop", args="<feature.spec path> … mode: unattended — implementation may
   already be complete: start by verifying, do NOT redo work")`. The **verify-first framing is what
   discriminates done from undone**: a feature already satisfied passes VERIFY on iteration 1 → green →
   `done` with **no rework**; an unsatisfied one fails VERIFY → the loop does real work. The gates are
   the *only* reliable "done" signal — `build-order` never guesses done-ness from a file's existence or
   name. The feature's **pre-approved** `loop.md` already sits in its spec dir (Phase 2). The **marker
   contract** (shared verbatim with the loop's R6 bypass) is: `mode: unattended` + a `loop.md` carrying
   the line `pre-approved-unattended: yes` → loop's Phase 0 skips its `AskUserQuestion` and runs the gates.
2. **Read the outcome from deterministic file signals — NOT from returned text.** The loop only
   *emits* its `## Loop Report`; nothing guarantees the verdict string comes back to a caller. So
   after the call, inspect the feature's spec dir:
   - a **fresh** `loop-escalation.md` (written this run) — or a **retained** `progress.md` — → the
     loop **escalated**;
   - a clean finish (`progress.md` deleted, no fresh escalation file) → the loop went **green**.
   Scope "fresh" to *this* run (clear/stamp `loop-escalation.md` before the call, or compare mtime) —
   `loop-escalation.md` persists across ticks. The `## Loop Report` text, if returned, is only a
   secondary cross-check.

### record(outcome)

| outcome | ledger | side effect |
|---------|--------|-------------|
| **green** | `status: done` | advance to the next ready feature |
| **escalated** | `status: parked, reason: escalated` | `PushNotification`; continue with features not transitively depending on it |
| **loop call itself errored** | `status: parked, reason: error` | `PushNotification`; continue (distinct from escalated, so morning triage tells a tooling failure from a real boundary) |

**Parked is sticky.** A `parked` feature is never auto-retried — it stays parked until a human edits
it back to `pending` (after fixing the cause). The cycle simply stops treating it as available.

### DEADLOCK — no ready feature, work remains

When the ready set is empty but features are still unfinished (all remaining are transitively blocked
by `parked` ones), **stop the run** and emit a `PushNotification` with a structured summary:
`done: [...]  /  parked: [(id, reason), ...]  /  blocked: [...]`. The human resolves the parked
features in the morning (un-parks → `pending`) and re-runs. `build-order` does not auto-retry parked
features before stopping.

---

## Phase 4 — Resume & Reconcile

A multi-hour unattended run **will** be compacted. `build_order.md` is what makes that survivable: on
resume, re-read it instead of re-planning.

### Resume — two levels
1. **Re-read `build_order.md`** — it already records which features are `done` / `parked` /
   `in-progress`, and the ready set is recomputed. No re-plan.
2. **Recover the `in-progress` feature** (drive is sequential, so there is at most one):
   - it has a `progress.md` → re-invoke its `/loop`; the loop resumes *within* the feature via ①'s
     `progress.md` (iteration, anti_spin, …). `build-order` records only **which** feature is current;
     the *where-inside* belongs to the loop.
   - it has **no** `progress.md` and **no** fresh escalation (a compact landed after `in-progress` was
     written but before the loop wrote anything — recall ① writes nothing on a single pass) →
     **re-invoke the loop from scratch**. Idempotent: loop's own Phase-0 absent-progress path just
     starts it. (This is why `in-progress` is flushed *atomically before* the loop call — the handoff
     is always recoverable.)
3. Continue the Phase-3 cycle normally.

### Reconcile — the input spec set changed since approval
Compare the current spec set against `build_order.md`'s `input_ref`:
- **Purely additive** (new specs) → **auto-merge**: append them as `pending` in topological position;
  preserve every existing `done` / `parked`. The unattended run continues.
- **Structural** (a spec removed, a `depends_on` edge changed, or a `done`-feature's spec content
  changed) → **pause and require human re-approval** of the reconciled `build_order.md` before the
  next cycle. Silently re-basing a human-approved plan — dropping a node another feature
  `depends_on`s, or mutating the ready set the human signed off on — is what the approval gate
  forbids. A changed `done`-feature spec is **flagged**, never silently kept or auto-re-run.

---

## Rules

1. **Sequence, don't verify** — `build-order` picks what runs next and records what happened; every
   gate / maker ≠ checker / lesson stays inside `/loop`. Never reimplement them.
2. **`build_order.md` is the durable source of truth** — atomic (temp + rename) writes; state never
   lives in ephemeral `TaskCreate`, so an overnight run survives compaction.
3. **Read outcomes from file signals** — `progress.md` / `loop-escalation.md` state, not by parsing
   the loop's returned report text.
4. **Sequential, deterministic next-ready** — one feature at a time; a resumed run selects the same
   current feature (topological, then declared order).
5. **Parked is sticky** — `escalated` / `error` / `no-spec` each park with a `reason`; only a human
   un-parks (→ `pending`). Never auto-retry a parked feature.
6. **Approve once, up front** — the plan AND every feature's gate contract, in one batch; no
   unattended run on an unapproved plan.
7. **Two-level resume** — `build_order.md` selects the feature; the loop's `progress.md` resumes
   within it. `build-order` never duplicates within-feature state.
8. **Reconcile: additive auto-merges, structural needs re-approval** — never silently re-base an
   approved ledger.
9. **Never push through the fence** — a feature's loop escalation parks that feature and surfaces it;
   `build-order` continues with independents but never overrides the loop's autonomy boundary.
