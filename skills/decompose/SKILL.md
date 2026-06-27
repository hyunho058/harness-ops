---
name: decompose
argument-hint: "\"<one project goal>\""
description: |
  Turn ONE project goal into N coherent, sibling-aware `specs/<feature>/spec.md`
  files — the optional MAKER front door to a multi-feature build. decompose proposes
  a PARTITION (split the goal into N features, each owning a *disjoint* declared-surface
  of path globs, with `depends_on` edges + per-feature `accept` seeds + the cross-cutting
  shared decisions made ONCE for the set), writes it to an atomic partition-manifest,
  runs its OWN deterministic overlap pre-flight, concentrates ALL human judgment at ONE
  partition gate (Approve / Revise / Abort), then drives `specify` in `mode: batch` per
  feature to elaborate each spec — and as its FINAL step calls `coherence-audit` on the
  generated files (maker ≠ checker on its own output). It REUSES specify's L0–L4
  derivation via batch mode; it never reimplements it, and never auto-resolves a conflict
  (it flags to the human). decompose : specify ∷ build-order : loop.
  Use when: "/decompose", "decompose", "decompose this goal", "split this goal into specs",
  "one goal into many specs", "partition into features", "sibling-aware specs", "batch
  specs from a goal", "generate a coherent spec set", "make N specs for a build".
  Do NOT trigger for: generating ONE spec (use /specify), checking an existing spec set
  (use /coherence-audit), or planning/driving a build (use /build-order or /autopilot).
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
---

# /decompose — One Goal → N Coherent Sibling-Aware Specs

Turn a **single project goal** into **N** build-order-ready `specs/<feature>/spec.md` files
that are coherent *by construction* — each owning a disjoint slice of the codebase, wired with
`depends_on` edges, and inheriting one set of shared decisions.

`decompose` is the **MAKER** and the **optional front door** to the spec-set pipeline. Today each
`/specify` is blind to its siblings, so hand-authored sibling specs can silently **overlap** (two
specs own the same files) or **contradict** (opposite decisions on a shared surface). decompose
closes that gap *up front*: it makes the cross-feature boundary decisions **once**, with the human,
at a single partition gate — and then automates the per-feature elaboration.

It does **not** reimplement spec generation. It **reuses `specify`** through its additive
`mode: batch` path, exactly as `build-order` reuses `loop` and `autopilot` reuses `build-order`:

```
decompose : specify  ∷  build-order : loop
```

Just as build-order needed loop's `pre-approved-unattended` bypass to batch-drive an interactive
engine, decompose needs specify's `mode: batch` bypass — it approves the *partition* once, then lets
specify derive each feature's L1–L4 with the human prompts skipped (but every non-interactive gate,
including specify's own L2-reviewer, still running).

---

## What it IS — and is NOT

| It IS | It is NOT |
|-------|-----------|
| the **maker**: one goal → N coherent sibling-aware specs | the checker — a *separate* judge (`coherence-audit`) audits its output |
| a **reuser** of specify's L0–L4 via `mode: batch` | a reimplementation of specify's derivation chain (forbidden) |
| a **partition** author: disjoint surfaces + `depends_on` + shared decisions | a "run /specify N times" loop — the load-bearing step is the partition |
| concentrates judgment at **ONE** human partition gate | an unattended auto-approver — it never proceeds without Approve |
| a **flagger**: a block-tier audit finding is surfaced to the human | an auto-resolver — it never silently rewrites a spec ("never push through the fence") |

---

## The partition manifest — decompose's load-bearing artifact

Everything coherent about the set is decided **once**, in a single artifact the human signs off and
`specify mode: batch` then consumes per feature. Its shape is fixed by the T1 contract
(`skills/coherence-audit/references/declared-surface-schema.md` §2) and templated at
`references/partition-manifest-template.md` — emit **exactly** those tokens so the
producer/consumer interface cannot drift.

- **Path:** `specs/<set>/partition-manifest.md` (`<set>` = the kebab batch name decompose derives
  from the goal; sibling-in-spirit to build-order's `build_order.md`).
- **Written atomically (temp file + rename), BEFORE any `spec.md` exists** — a crash mid-write must
  never leave a torn manifest the human might approve.
- Per feature it carries the `{ feature-id, declared-surface (globs), depends_on, accept-seed }`
  tuple + a `pre-approved-batch:` line (starts `no`), and one top-level `## Shared Decisions` block
  every generated spec inherits verbatim.

---

## The pipeline

Six steps. The judgment is concentrated entirely at step 4; everything before it is preparation,
everything after it is mechanical reuse + an independent check.

### 1. Derive the partition  (R1.1, D10)

From the ONE goal, propose a partition — do NOT call specify yet:

- **Split into N features**, each owning a **disjoint declared-surface** expressed as repo-root-relative
  **path globs** (e.g. `src/auth/**`, `app.py`). N is proposed from the goal's *natural seams* — it is
  **not fixed**, and N itself is part of what the human approves.
- **Derive `depends_on` edges** from cross-feature references (a feature that builds on another's
  surface `depends_on` it). `[]` = a root. Order them topologically in the manifest.
- **Seed each feature's `accept`** — a one-line acceptance seed (flows to the spec's R0 sub-requirement
  and build-order's ledger `accept:`).
- **Decide the shared decisions ONCE** — the cross-cutting tech/architecture choices that apply to the
  WHOLE set, as `## Shared Decisions` / `SD<n>` entries (every generated spec inherits these verbatim).

Aim for **disjoint** surfaces. Where a later feature legitimately extends an earlier one's file, model
it as an **ordered** share (a `depends_on` edge) — never as an unordered collision.

### 2. Write the manifest — atomically  (R1.1)

Write `specs/<set>/partition-manifest.md` per the template, **atomically (temp + rename)**, with every
feature's `pre-approved-batch: no`:

```bash
mkdir -p "specs/<set>"
# write the full manifest to a temp file in the SAME directory, then atomically rename:
#   ...write specs/<set>/.partition-manifest.md.tmp ...
mv "specs/<set>/.partition-manifest.md.tmp" "specs/<set>/partition-manifest.md"
```

The manifest is the single source the human approves and that batch-mode specify consumes per feature.
It does **not** generate any `spec.md` yet.

### 3. Deterministic overlap PRE-FLIGHT — decompose's OWN logic, NOT a skill call  (R1.2, D10)

Before spending tokens generating N specs, fail fast on a **self-inflicted overlap**. Run the overlap
tier's **glob set-intersection** (the T1 §1 glob semantics — `*`/`?` = one segment, `**` = zero+ whole
segments; two surfaces overlap iff ANY glob in one intersects ANY glob in the other) over the manifest's
own `declared-surface:` lists:

- Build the feature graph from the manifest's `depends_on`. A pair is **ordered** iff a `depends_on`
  path exists either way (direct **or transitive**); else **unordered**.
- An **UNORDERED** pair with a non-empty glob intersection → **FAIL FAST**: surface the offending
  `(feature-A, feature-B)` and the intersecting `(globA, globB)` pair, and STOP before generating any
  spec. Revise the partition (step 1) and re-run.
- An **ORDERED** shared pair is legitimate (B extends A's surface *after* A) — not a failure (mirrors
  the overlap tier's dependency-gating, R2.3).

This pre-flight makes **NO contradiction claim** — the manifest carries no per-feature `## Decisions`
yet, so contradiction is *structurally undetectable* until the specs exist. It is **decompose's own
internal logic over the manifest it just wrote** — NOT a `coherence-audit` call — so it does **not**
violate coherence-audit's "reads spec files only" contract. (The real cross-spec contradiction check
happens at step 6, on the generated spec FILES.)

### 4. ONE human partition gate — the judgment-concentration point  (R1.3, D5)

Present the pre-flighted partition and ask for a single approval. This is the ONE gate D5 leans its
safety on: the human owns the bar here, so specify's per-feature prompts can be safely skipped.

```
AskUserQuestion(
  question: "Approve this partition? <N> features, their declared surfaces (globs),
             the depends_on edges, and the shared decisions for the whole set are shown above.",
  options: [
    { label: "Approve", description: "Boundaries + edges + shared decisions are right — generate the specs" },
    { label: "Revise",  description: "Change the features / surfaces / edges / shared decisions first" },
    { label: "Abort",   description: "Stop — generate nothing" }
  ]
)
```

- **Approve** → proceed to step 5. Flip **every** feature's `pre-approved-batch: no` → `yes` in the
  manifest (atomic rewrite) — this is the specify-batch pre-approval line (T1 §3), written ONLY now,
  after the human approved.
- **Revise** → apply the corrections to the partition, re-write the manifest (step 2), re-run the
  pre-flight (step 3), re-present. Loop until Approve.
- **Abort** → stop. Generate nothing.

**Proceed ONLY on Approve.** No spec is generated, and no `pre-approved-batch` is flipped, otherwise.

### 5. Drive specify in batch mode — per feature  (R1.4, D5, R2.1)

For each feature in the approved manifest (topological order), drive `specify` in batch mode. Pass the
**exact T1 §3 tokens**: the invocation marker `mode: batch` plus the feature + manifest entry that now
carries `pre-approved-batch: yes` (the bypass fires only with BOTH present):

```
Skill(skill="harness-ops:specify",
      args="mode: batch
feature-id: <feature-id>
manifest: specs/<set>/partition-manifest.md")
```

specify writes `specs/<feature-id>/spec.md`, and in batch mode:

- **EMITS the `## Declared Surface` section** (R2.1) — the owned path globs + `depends_on`, copied
  **verbatim** from the feature's manifest entry. This is the producer half of the declared-surface
  contract (coherence-audit is the consumer).
- **Inherits `## Shared Decisions` (`SD<n>`) verbatim** at the top of the spec's `## Decisions`, then
  derives that feature's local decisions below them.
- **Seeds Requirements / `accept`** from the manifest `accept-seed` (build-order-ready, D9).
- **Skips only the human `AskUserQuestion` prompts** (L0 mirror; L2/L3/L4 approvals) — every
  non-interactive gate STILL runs, including specify's per-spec **L2-reviewer** subagent (the
  within-spec maker ≠ checker). decompose does **not** reimplement any of specify's L0–L4 derivation.

Collect the generated path `specs/<feature-id>/spec.md` for each feature — that resolved set is the
input to step 6.

### 6. decompose-end coherence-audit — maker ≠ checker on decompose's OWN output  (R1.5, D10)

As the **FINAL** step, hand the just-generated spec FILES to the independent checker. decompose is the
maker; `coherence-audit` is a *separate* judge — it reads the spec files only (never decompose's
reasoning or the manifest), so the emitted set is independently contradiction-checked **even on this
standalone path** (no build-order follow-on required):

```
Skill(skill="harness-ops:coherence-audit",
      args="specs/<feature-a>/spec.md specs/<feature-b>/spec.md ...")
```

Pass the explicit generated spec paths (coherence-audit's "audit exactly these paths" form — the
already-resolved set); passing the `specs/<set>` dir is the equivalent alternative. Then read the
`verdict:` token **from the emitted `coherence-report.md`** (a deterministic file signal — coherence-audit's
return contract; its return message states the verdict as a secondary cross-check), and branch:

| verdict | meaning | decompose does |
|---------|---------|----------------|
| `BLOCK` | ≥1 block-tier finding — a contradiction OR an unordered overlap | the set is **NOT done**. **Surface the finding to the initiating human and STOP** — never auto-resolve, never rewrite a spec. The human resolves (e.g. reconcile the decisions, or add a `depends_on` edge), then re-runs. |
| `WARN`  | only redundancy / undeclared surfaces | report the warnings; the set stands (non-blocking). |
| `OK`    | no findings | the set is coherent for what is declared — done. |

A **block-tier** finding marks the set not-done and is surfaced to the human who initiated decompose —
**NEVER auto-resolved** ("never push through the fence"). This is maker ≠ checker applied to decompose's
OWN output: decompose authored the specs, a separate judge grades them, and decompose does not overrule
that judge.

---

## Where decompose-end fits the two-point audit

`coherence-audit` runs on the generated spec FILES at **two** points (both authoritative for their
scope; the "reads spec files only" contract is never violated — the step-3 pre-flight is decompose's own
logic over its manifest, not a skill call):

1. **decompose-end** (step 6, this skill) — checks the set decompose just emitted, on the standalone path.
2. **build-order Plan** (T4 / D4) — re-checks the full set build-order is about to drive (which may mix in
   hand-written or since-edited specs).

Distinct stages, distinct inputs — intentional, idempotent defense-in-depth, not redundant work.

---

## Rules — the hard invariants

1. **Reuse specify, never reimplement it.** decompose drives `specify` via `mode: batch` for ALL L0–L4
   derivation. It contains no L1 research / L2 decisions / L3 requirements / L4 tasks logic of its own.
2. **The partition is the load-bearing step.** What makes decompose more than "run /specify N times" is
   the partition: disjoint surfaces, `depends_on` edges, and shared decisions made ONCE — approved at a
   single human gate.
3. **ONE human gate; proceed only on Approve.** All cross-feature judgment concentrates at the partition
   gate. No spec is generated, and no `pre-approved-batch` flips to `yes`, without an explicit Approve.
4. **The manifest write is atomic** (temp + rename) and happens **before** any spec is generated.
5. **The pre-flight makes no contradiction claim.** It is decompose's own deterministic overlap check
   over the manifest (NOT a coherence-audit call); contradiction is undetectable until specs exist.
6. **Maker ≠ checker.** decompose authors; `coherence-audit` (a separate judge) grades. decompose calls
   it at decompose-end and **branches on its verdict** — it never self-certifies its own output.
7. **Never auto-resolve a conflict — never push through the fence.** A block-tier finding is surfaced to
   the human and the set is marked not-done. decompose never rewrites a spec to silence a finding.
8. **Emit the exact T1 tokens.** `## Declared Surface` + `declared-surface:` + `depends_on:` in each spec
   (R2.1), the `## Shared Decisions` / `SD<n>` block + `pre-approved-batch:` line in the manifest, and the
   `mode: batch` marker on each specify call — bound to
   `skills/coherence-audit/references/declared-surface-schema.md`, never redefined.
9. **Reuse the existing skills byte-unchanged.** decompose only *calls* specify (batch) and
   coherence-audit; it alters neither, and touches neither loop, build-order, nor autopilot.
