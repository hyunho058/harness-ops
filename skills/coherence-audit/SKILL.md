---
name: coherence-audit
argument-hint: "[spec paths or a specs dir | default: specs/*/spec.md]"
description: |
  Independently check a SET of feature specs for cross-spec incoherence before an
  (often unattended) build runs. Reads spec FILES only — never a decomposer's
  reasoning (maker ≠ checker) — and flags three things: declared-surface OVERLAP
  (two independent features own the same files, deterministic glob set-intersection),
  CONTRADICTION (incompatible `## Decisions` on a shared surface, judged by a SEPARATE
  subagent), and REDUNDANCY (near-duplicate Requirements/goal). Emits a
  coherence-report.md and yields one machine-readable verdict — BLOCK | WARN | OK —
  that a caller branches on. It is FLAG-ONLY: it never edits or rewrites a spec
  ("never push through the fence"). Runs standalone on any spec set, AND is called by
  build-order at the end of Plan and by decompose at decompose-end.
  Use when: "/coherence-audit", "coherence audit", "audit the spec set", "check these
  specs for overlap", "do my specs contradict", "are these specs coherent", "cross-spec
  conflict check", "coherence-report", "check spec set before build".
  Do NOT trigger for: generating specs (use /specify or /decompose), planning a build
  order (use /build-order), or verifying ONE feature's gates (use /loop).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Agent
---

# /coherence-audit — Cross-Spec Coherence Checker

Check a **set** of feature specs for incoherence *before* a build drives them.

When a user authors (or `/decompose` generates) many sibling `spec.md` files to feed an
unattended `build-order` / `autopilot` run, each spec was written blind to its siblings. Two
specs can silently **overlap** (both own the same files → a last-writer-wins collision) or
**contradict** (opposite `## Decisions` on the same surface). This skill is the independent
cross-spec checker that surfaces those conflicts to a human **before** approval — the spec-SET
analogue of specify's within-spec `L2-reviewer`, lifted from one spec to the whole set.

It is an **independent verifier**, not an author. It reads the spec **files only** — never the
decomposer's reasoning or its partition manifest (maker ≠ checker). And it is **flag-only**: it
WRITES a `coherence-report.md` and **nothing else** — it NEVER edits or rewrites a `spec.md`
("never push through the fence", R7.3). The human (or the calling skill — build-order /
decompose) resolves every finding; the checker only surfaces them.

---

## What it is — and is NOT

| It IS | It is NOT |
|-------|-----------|
| an independent **cross-spec** checker (maker ≠ checker) | the decomposer / a spec author — it never writes a spec |
| a **flag-only** reporter — writes `coherence-report.md` only | a fixer — it never edits or rewrites a spec (R7.3) |
| reads real `spec.md` files (`## Declared Surface`, `## Decisions`) | a reader of decompose's reasoning / manifest (it reads spec files only) |
| a substitute for the *within*-spec L2-reviewer? **No** | — the L2-reviewer still runs per spec; this is a *cross*-spec layer on top |

---

## Invocation & return contract  (callers bind to THIS)

**Invocation interface** — what to scan:
- `coherence-audit` (no args) → **default**: scan `specs/*/spec.md` (every feature spec in the repo).
- `coherence-audit <dir>` → scan `<dir>/*/spec.md` (a named spec-set directory).
- `coherence-audit <spec1> <spec2> …` → audit **exactly** the listed `spec.md` paths (how
  build-order and decompose pass their already-resolved set).

**Return contract** — what a caller gets back:
1. It **writes** a `coherence-report.md` (the layout, the R3.3 per-pair schema, and the overall
   verdict token are fixed by `references/coherence-report-template.md` — emit EXACTLY that).
   Written **atomically** (temp file + rename) so a crash mid-write can't tear it. Location: the
   audited set's directory if one is identifiable (e.g. `specs/<set>/coherence-report.md`), else
   repo root, or a path the caller names.
2. It yields one **machine-readable overall verdict** — the report header line
   `verdict: BLOCK | WARN | OK`. A caller **branches on this token**, and reads it
   **from the report file** (a deterministic file signal — mirroring build-order's "read outcomes
   from file signals, not returned text" rule); the skill also states the verdict in its return
   message as a secondary cross-check.

```
verdict: BLOCK   → ≥1 block-tier finding (a contradiction OR an unordered overlap). HARD-STOP an
                   unattended / pre-batched approval — a human must resolve before the build runs.
verdict: WARN    → only warn-tier findings (redundancy and/or undeclared surfaces). Annotated,
                   non-blocking — surface to the human but do not halt.
verdict: OK      → no findings. The set is coherent for what is declared.
```

The checker **never asks** and **never auto-resolves**: it returns the verdict; the caller owns the
human interaction (build-order's Phase-2 Approve, decompose's initiating human).

---

## What it reads — the T1 declared-surface contract

Bind to `references/declared-surface-schema.md` and **consume its tokens verbatim — do not
redefine them**. Per spec, read:

- **`## Declared Surface`** section (the heading is what the declared-vs-undeclared check keys on):
  - **`declared-surface:`** — the bullet list of owned **path globs** (what the overlap check reads).
  - **`depends_on: [<feature-id>, …]`** — feature-level edges (`[]` = a root); the overlap gate
    reads this. Same field build-order topo-orders on.
  - **`feature-id`** — defaults to the spec's directory name (`specs/<feature-id>/spec.md`); the
    resolution key for `depends_on`.
- **`## Decisions`** — each decision's title + Rationale (incl. rejected alternatives). Inherited
  **`## Shared Decisions` / `SD<n>`** entries are common ground (made once for the set); only
  divergent feature-local `D<n>` decisions on a shared surface are contradiction candidates.
- **Requirements / Goal** — for the redundancy tier.

**Glob semantics are owned by the schema** (§1: normalization; `*`/`?` = one segment, `**` = zero+
whole segments; two surfaces overlap iff ANY glob in A overlaps ANY glob in B; evidence = the
`(globA, globB)` pair). Apply them; do not restate or re-invent them.

---

## The audit pipeline

Mirrors loop's **deterministic vs judged** split (its Gate-1 deterministic / Gate-3 judged
separate-scorer model, D7): the overlap and redundancy tiers are deterministic, so the maker runs
them; the contradiction tier is a judgement, so a **separate subagent** runs it (maker ≠ checker).

### 1. Gather  (per spec)
Read each spec's `## Declared Surface` (globs + `depends_on`), `## Decisions` (incl. inherited
`SD<n>`), and Requirements/Goal. **Classify declared vs undeclared (D8):** a spec is **surface
undeclared** iff it has no `## Declared Surface` section OR its `declared-surface:` list is
empty/absent. For each undeclared spec emit a WARN with the **verbatim** string:

> `surface undeclared; overlap unverifiable — declare to enable the check`

Absence ≠ conflict — an undeclared surface is **WARN-tier only**; never hard-block on absence alone
(D8 / R2.4). Then build the feature dependency graph from every spec's `depends_on` (for the gate
below). A pair (A, B) is **ordered** iff a directed `depends_on` path exists A→…→B *or* B→…→A
(direct **or transitive**); otherwise it is **unordered**.

### 2. Overlap tier — DETERMINISTIC, maker-run  (R2.2, R2.3, D2)
For every pair of *declared* specs, compute the **glob set-intersection** per the schema's glob
semantics — deterministic, not judged (same inputs → same verdict). A non-empty intersection means
the pair **shares a surface**. Then **dependency-gate** the flag:

- **Unordered** shared pair (no `depends_on` path either way) → **FLAG: overlap, BLOCK-tier**
  (the last-writer-wins collision D2 isolates as a real hazard). Evidence = the intersecting
  `(globA, globB)` pair(s).
- **Ordered** shared pair (a `depends_on` path orders them) → **NOT flagged** for overlap — ordered
  sharing is legitimate (B extends A's file *after* A is done). Record it under the report's
  **"Considered, not flagged → ordered overlaps"** section (audit completeness; does not affect the
  verdict).

The set of **pairs sharing a surface** (ordered *and* unordered) is handed forward to tier 3 — the
contradiction tier is **un-gated** and runs over all of them.

### 3. Contradiction tier — JUDGED, a SEPARATE subagent  (R3.1, R3.2, D7)
A contradiction is a **judgement**, and the checker must not grade decisions it could be biased
about — so a **separate judge subagent** runs this tier, **never the decomposer** (maker ≠ checker).
Spawn it via the **`Agent`** tool (the same mechanism specify's `L2-reviewer` and loop's Gate-3
checker use). Hand it **only** the spec files' `## Decisions` for the pairs sharing a surface —
**not** any decomposer reasoning or manifest (the separation is the whole point). The comparison is
**un-gated by dependency order** (D2-scope): ordering makes write-*timing* deterministic but never
makes two opposite Decisions coherent, so an ordered pair can still contradict.

```
Agent(subagent_type="general-purpose", prompt="""
You are an INDEPENDENT cross-spec contradiction judge. You did NOT author these specs
(maker ≠ checker) and you have NOT seen any decomposer reasoning, manifest, or task notes —
only the spec files' `## Decisions`. Judge contradiction from the cited decisions alone.

For each pair of specs that SHARE a declared surface (handed to you below — both ordered and
unordered pairs; contradiction is un-gated by depends_on), you are given, per spec:
  - feature-id, the shared path(s) they both declare
  - that spec's `## Decisions`: each as title + Rationale (including its rejected alternatives)
Inherited `## Shared Decisions` / `SD<n>` entries that are IDENTICAL in both specs are shared
common ground — NEVER a conflict. Only DIVERGENT feature-local `D<n>` decisions that act on the
shared surface are contradiction candidates.

Classify each shared surface:
  - INCOMPATIBLE — same role on the shared path, conflicting choice (e.g. both claim the primary
    datastore but pick different engines). → block
  - COMPLEMENTARY — different roles on one path (e.g. A owns storage, B owns a cache under db/**).
    → NOT a conflict.

Return, per pair, the R3.3 schema: { pair: A ⨯ B, shared-path, classification: incompatible |
complementary, evidence: A `D<i>: <title>` (chose <x>; rejected <y>) vs B `D<j>: <title>`
(chose <z>) — same role on <shared path>, verdict: block | ok }. CITE the exact Decision
ids + titles — a bare verdict with no cited Decision evidence is invalid. Only INCOMPATIBLE blocks.
""")
```

**Result:** each **incompatible** pair → **FLAG: contradiction, BLOCK-tier**, with the cited
Decision evidence. Each **complementary** pair → **NOT a conflict**; record it under the report's
**"Considered, not flagged → complementary shares"** section.

**Fallback — no `Agent` tool in this environment** (mirrors loop's Gate-3 fallback): do **not**
silently pass the contradiction tier. Label it `unverified` in the report and treat any
shared-surface pair as unresolved — never return a clean `OK` over an unjudged shared surface.
Maker ≠ checker is a hard invariant: an un-judged contradiction tier is surfaced, not hidden.

### 4. Redundancy tier — advisory, maker-run  (R3.4)
Detect **near-duplicate Requirements/goal** across specs. → **FLAG: redundancy, WARN-tier**
(advisory only — duplication is a smell, not a write-hazard). Evidence = the near-duplicate text
from each spec.

---

## Verdict — severity-tiered  (R4.1–R4.3, D3)

Two tiers, severity-matched. Compute the overall token from the findings:

| Finding | Tier | Why |
|---------|------|-----|
| **contradiction** (incompatible Decisions on a shared surface) | **BLOCK** | a provable hazard — opposite choices can't both be built |
| **unordered overlap** (independent features, no `depends_on` path, same surface) | **BLOCK** | a provable hazard — last-writer-wins write collision |
| **redundancy** (near-duplicate Requirements/goal) | warn | advisory — duplication, not a collision |
| **undeclared** surface (no `## Declared Surface` / empty list) | warn | unverifiable, not a proven conflict (D8) |

**Overall verdict:**
- **`BLOCK`** — iff ≥1 block-tier finding (a contradiction OR an unordered overlap). [R4.1]
- **`WARN`** — no block-tier findings but ≥1 warn-tier finding (redundancy and/or undeclared). [R4.2]
- **`OK`** — no findings.

**CRITICAL — an unordered overlap BLOCKS, it never warns (R4.3).** In a pre-batched / autopilot
path the human approval was given up front, so at Phase-2 there is **no human reading a WARN** — a
WARN there is an *unread annotation*. A known write-collision must therefore **hard-stop** the run,
not annotate it, or it would proceed to clobber unseen. This is the whole reason the unordered
overlap sits in the BLOCK tier and not the WARN tier.

---

## The report — `coherence-report.md`

Emit **exactly** the layout in `references/coherence-report-template.md` (header with
`verdict: BLOCK | WARN | OK` + `specs_audited` + `input_ref`; the **Summary** tier table; the
**Findings** section — one block per conflicting pair / flagged spec in the R3.3 schema
`{verdict, cited evidence, block|warn}`; the **"Considered, not flagged"** section for ordered
overlaps and complementary shares; and the **Verdict** section naming the rule that produced it).

- `input_ref` = a fingerprint of the audited set (sorted feature-ids + spec paths) — so a caller can
  tell *which* set this report covers (mirrors build-order's `input_ref`).
- The report is the **only** thing the checker writes. It writes no spec, edits no spec (R7.3).

---

## Invocation paths — standalone, build-order, decompose

The same skill, the same return contract, three entry points:

1. **Standalone** — `/coherence-audit [paths|dir]` on any hand-written or incrementally `/specify`'d
   spec set. Writes the report; returns the verdict for the human to read.
2. **build-order Plan (T4 / D4, R6.1)** — build-order calls
   `Skill(skill="harness-ops:coherence-audit")` at the **end of Phase 1 (Plan)**, before the Phase 2
   Approve, passing the classified spec set. A **BLOCK** surfaces at the existing batch-Approve and
   prevents an unattended run from proceeding unapproved (R6.2). build-order's gating logic is
   unchanged — only the call is added (R6.3).
3. **decompose-end (T3 / R1.5, D10)** — as decompose's FINAL step it calls coherence-audit on the
   specs it just generated, so the emitted set is independently contradiction-checked even on the
   standalone path. A **BLOCK** marks the set **not-done** and is surfaced to the initiating human —
   **never auto-resolved** (maker ≠ checker applied to the decomposer's own output).

In every path the checker reads the real generated `spec.md` files (their `## Declared Surface` /
`## Decisions`) — never decompose's reasoning or manifest. The two call sites are distinct
stages/inputs: intentional, idempotent defense-in-depth, not redundant work.

---

## Rules

1. **Flag-only — never push through the fence.** The checker WRITES `coherence-report.md` and
   nothing else. It **never** edits or rewrites a `spec.md` (R7.3). The human / calling skill
   resolves every finding; the checker never auto-resolves.
2. **Reads spec files only.** It reads real `spec.md` files (`## Declared Surface`, `## Decisions`,
   Requirements) — never decompose's reasoning, manifest, or task notes (maker ≠ checker, across the
   whole pipeline).
3. **Maker ≠ checker on contradiction.** The contradiction tier is run by a **separate `Agent`
   subagent** — never the decomposer, and never handed the maker's reasoning. No `Agent` tool →
   label the tier `unverified`; never silently pass it.
4. **Deterministic where possible.** Overlap (glob set-intersection) and redundancy are
   deterministic and maker-run; only contradiction is judged. Same inputs → same overlap verdict.
5. **Overlap is dependency-gated; contradiction is NOT.** Overlap flags only an **unordered** pair
   (no `depends_on` path, direct or transitive); an ordered shared pair is legitimate and recorded
   "considered, not flagged". Contradiction runs over the **un-gated** shared surface.
6. **Severity-tiered, and an unordered overlap BLOCKS — never warns.** BLOCK = contradiction OR
   unordered overlap; WARN = redundancy or undeclared. In an unattended/pre-batched path a WARN is
   unread, so a known write-collision must hard-stop (R4.3).
7. **Undeclared degrades to WARN, never a hard block on absence** (D8) — emit the verbatim
   `surface undeclared; overlap unverifiable — declare to enable the check`; keep the checker usable
   on any spec set without forcing migration.
8. **Return a machine-readable verdict.** The overall `verdict: BLOCK | WARN | OK` lives in the
   report header; a caller reads it from the report file (deterministic file signal) and branches on
   it. The skill reuses the existing skills byte-unchanged — it only adds a call site for callers.
