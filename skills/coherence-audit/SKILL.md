---
name: coherence-audit
argument-hint: "[spec paths or a specs dir | default: specs/*/spec.md] [report: <path>]"
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

> **Runtime contract — read this first.** Before executing any step below, read
> `../../references/runtime-tools.md`. This skill names **capabilities**, not runtime tool
> names, and cites pinned **procedure ids** (`` `capability:<id>` ``) wherever the outcome
> depends on running exactly that procedure. The map turns each one into the concrete call for
> the runtime you are in. Do not substitute your own reasoning for a cited procedure id.

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

**Named token** — where to write the report (R2.3, D14):
- `report: <path>` → write the `coherence-report.md` to **exactly** that path. Combines with any of
  the three forms above, e.g. how decompose calls it:
  `coherence-audit specs/session-core/spec.md specs/auth/spec.md report: specs/login-stack/coherence-report.md`.
- It is a **named** token, never a positional argument: the positional slot is already overloaded
  (`<dir>` vs `<spec paths>`), so an unnamed path would be ambiguous with a spec path — and every
  other cross-skill interface in this harness is a named token (`mode: batch`,
  `pre-approved-batch: yes`).
- When `report:` is present it **takes precedence** over the default location rule below.

**Return contract** — what a caller gets back:
1. It **writes** a `coherence-report.md` (the layout, the R3.3 per-pair schema, and the overall
   verdict token are fixed by `references/coherence-report-template.md` — emit EXACTLY that).
   Written **atomically** (temp file + rename) so a crash mid-write can't tear it.
   **Location — a caller-named `report:` wins:** if the invocation carries `report: <path>`, the
   report goes to exactly that path and nothing else decides it (R2.3). Only absent that token does
   the fallback apply: the audited set's directory if one is identifiable (e.g.
   `specs/<set>/coherence-report.md`), else repo root.
2. It yields one **machine-readable overall verdict** — the report header line
   `verdict: BLOCK | WARN | OK`. A caller **branches on this token**, and reads it
   **from the report file** (a deterministic file signal — mirroring build-order's "read outcomes
   from file signals, not returned text" rule); the skill also states the verdict in its return
   message as a secondary cross-check.

```
verdict: BLOCK   → ≥1 block-tier finding (a contradiction OR an unordered overlap), OR any tier
                   reported `unverified` (a check that could not run at all — D8/R7.4). HARD-STOP
                   an unattended / pre-batched approval — a human must resolve before the build runs.
verdict: WARN    → only warn-tier findings (redundancy and/or undeclared surfaces), and every tier
                   actually ran. Annotated, non-blocking — surface to the human but do not halt.
verdict: OK      → no findings AND every tier actually ran. The set is coherent for what is declared.
```

These are the **only** three tokens a caller ever sees. A tier that could not run is labelled
`unverified` in the report and **resolves to `BLOCK`** — a label that resolved to nothing would
leave callers unable to branch (see the verdict table below).

The checker **never asks** and **never auto-resolves**: it returns the verdict; the caller owns the
human interaction (build-order's Phase-2 Approve, decompose's initiating human).

---

## What it reads — the T1 declared-surface contract

Bind to `references/declared-surface-schema.md` via `capability:read-declared-surface-schema` and
**consume its tokens verbatim — do not redefine them**. That id is pinned rather than a plain read
because the verdict depends on these normalization rules exactly; a paraphrase of them changes
outcomes. Per spec, read:

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

**NOT spec content — line 1's `<!-- decompose-entry: <feature-id> @ sha256:<digest> -->`** (schema
§1). This HTML comment is **machine-owned metadata**: decompose stamps it to tell "the SOURCE
changed" apart from "the HUMAN edited the artifact" on its own resume. It is **not** part of
`## Decisions`, not a requirement, not prose, and **never material for the contradiction tier,
the redundancy tier, or any judged finding** — a changed digest is a bookkeeping difference, never
a semantic one. Skip it when gathering and never hand it to the judge subagent. A spec **without**
the marker is a pre-marker spec, not an error — the audit reads it exactly as it always has.

**Glob semantics are owned by the schema** (§1: normalization; `*`/`?` = one segment, `**` = zero+
whole segments; two surfaces overlap iff ANY glob in A overlaps ANY glob in B; evidence = the
`(globA, globB)` pair) — and §1's "normative implementation" subsection binds them to the shared
script tier 2 calls. Apply them; do not restate or re-invent them.

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

### 2. Overlap tier — DETERMINISTIC, computed by the shared script  (R2.2, R2.3, R7.2, D2, D7, D11, D13)
The glob set-intersection is **run, not reasoned about**. Do **not** judge overlap in prose: invoke
the one shared implementation of schema §1 — the same script decompose's step-3 pre-flight calls, so
**when both invoke it** the two skills return the **identical verdict for the same pair**:

Run `capability:run-glob-overlap` — the map pins the exact command for your runtime, built on the
absolute root from `capability:resolve-harness-root`:

```
<harness-root>/skills/coherence-audit/scripts/glob-overlap.sh <surface-a-file> <surface-b-file>
```

**Per pair of *declared* specs (A, B):**

1. **Build the two surface files.** Write A's `declared-surface:` globs to a temp file — **one bare
   glob per line**, with the `- ` bullet prefix **stripped** (the script does not strip it; a
   leftover `- ` is a malformed glob). Same for B into a second file. Globs never travel through
   argv, so no shell can expand one against the real filesystem.
2. **Run the script and branch on the EXIT STATUS** — the status is the verdict, not the prose:

| Exit | Meaning | What the tier does |
|------|---------|--------------------|
| `0` | **disjoint**; stdout empty | the pair does not share a surface — nothing to gate, nothing to report |
| `1` | **intersecting**; stdout = one `<globA>`TAB`<globB>` line per intersecting pair | the pair **shares a surface**; stdout **is** the evidence — dependency-gate it below |
| `2` | usage / IO error (diagnostics on stderr, stdout empty) | this pair's check did **not** run → take the `unverified` fallback below |

An **empty** surface is not an error: the script returns `0` (disjoint). Absence is a WARN-tier
signal owned by tier 1's declared-vs-undeclared classification — the script never swallows it.

**Then dependency-gate the flag. The gating stays HERE, in the caller** — the script computes the
pure intersection and contains no gating, because the two callers legitimately differ: decompose
gates against the **manifest's** `depends_on`, coherence-audit against the **specs'**.

- **Unordered** shared pair (no `depends_on` path either way) → **FLAG: overlap, BLOCK-tier**
  (the last-writer-wins collision D2 isolates as a real hazard). Evidence = the intersecting
  `(globA, globB)` pair(s) **exactly as the script printed them** — normalized globs, A-major
  order. Do not re-derive or re-word the evidence.
- **Ordered** shared pair (a `depends_on` path orders them) → **NOT flagged** for overlap — ordered
  sharing is legitimate (B extends A's file *after* A is done). Record it under the report's
  **"Considered, not flagged → ordered overlaps"** section (audit completeness; does not affect the
  verdict).

The set of **pairs sharing a surface** (ordered *and* unordered) is handed forward to tier 3 — the
contradiction tier is **un-gated** and runs over all of them.

**Fallback — the check could not run (R7.4, D8, D16, D22).** Two shapes, one policy:
**tier-wide** — the script is missing, not executable, or the harness root does not validate
(plausible on the plain `.claude/skills/` stub-symlink path); or **pair-scoped** — the script exits
`2` on a pair (a malformed glob; diagnostics on stderr). In **neither** case does coherence-audit
hard-fail. It is flag-only: it writes a report and halts nothing (Rule 1), and a report that
honestly says "unverified" is more useful than no report at all. Take the same path this skill
already ships when the checker capability is unavailable (tier 3 below):

- **Label the tier `unverified`** in the report, naming what was unavailable (or, for an exit `2`,
  quoting the script's stderr and the pair it applies to).

Name *which* tier-wide failure occurred — the three are not interchangeable and their fixes differ
(see the map's Halting table):

- `unresolved: harness root did not validate at <path>` — `capability:resolve-harness-root` failed
  its `skills/` + `agents/` probes.
- `denied: run-command requires permission not granted` — the command capability exists but was
  refused. Antigravity's headless `-p` mode auto-denies it; an allow-rule or an interactive run
  fixes it. **This is not a missing capability**, and reporting it as one sends the reader to the
  wrong fix.
- `unavailable: <procedure> not provided by <runtime>` — genuinely absent here.
- **Treat the affected pairs as unresolved** — tier-wide, that is every pair of declared specs,
  because which pairs actually share a surface is precisely what could not be computed; hand that
  un-narrowed pair set forward to tier 3 rather than a narrowed one.
- **Never return a clean `OK`** over an overlap check that never ran. **`unverified` resolves to
  `verdict: BLOCK`** — see the verdict table.
- Do **NOT** fall back to inline LLM reasoning (it silently reintroduces the non-determinism the
  script exists to remove) and do **NOT** fall back to a relative path (it resolves against the
  user's repo root, where it could match an unrelated file).

### 3. Contradiction tier — JUDGED, a SEPARATE subagent  (R3.1, R3.2, D7)
A contradiction is a **judgement**, and the checker must not grade decisions it could be biased
about — so a **separate judge subagent** runs this tier, **never the decomposer** (maker ≠ checker).
Spawn it with `capability:spawn-inline-checker` — its prompt is written inline below, so there
is no `agents/<name>.md` to source (the same mechanism specify's `L2-reviewer` and
loop's Gate-3 checker use). Hand it **only** the spec files' `## Decisions` for the pairs sharing a surface —
**not** any decomposer reasoning or manifest (the separation is the whole point). The comparison is
**un-gated by dependency order** (D2-scope): ordering makes write-*timing* deterministic but never
makes two opposite Decisions coherent, so an ordered pair can still contradict.

Give the checker this prompt:

```
You are an INDEPENDENT cross-spec contradiction judge. You did NOT author these specs
(maker ≠ checker) and you have NOT seen any decomposer reasoning, manifest, or task notes —
only the spec files' `## Decisions`. Judge contradiction from the cited decisions alone.

For each pair of specs that SHARE a declared surface (handed to you below — both ordered and
unordered pairs; contradiction is un-gated by depends_on), you are given, per spec:
  - feature-id, the shared path(s) they both declare
  - that spec's `## Decisions`: each as title + Rationale (including its rejected alternatives)
Inherited `## Shared Decisions` / `SD<n>` entries that are IDENTICAL in both specs are shared
common ground — NEVER a conflict. Only DIVERGENT feature-local `D<n>` decisions that act on the
shared surface are contradiction candidates. A line-1 `<!-- decompose-entry: … -->` HTML comment
is machine-owned metadata, NOT spec content — never cite it and never treat a differing digest as
a semantic difference.

Classify each shared surface:
  - INCOMPATIBLE — same role on the shared path, conflicting choice (e.g. both claim the primary
    datastore but pick different engines). → block
  - COMPLEMENTARY — different roles on one path (e.g. A owns storage, B owns a cache under db/**).
    → NOT a conflict.

Return, per pair, the R3.3 schema: { pair: A ⨯ B, shared-path, classification: incompatible |
complementary, evidence: A `D<i>: <title>` (chose <x>; rejected <y>) vs B `D<j>: <title>`
(chose <z>) — same role on <shared path>, verdict: block | ok }. CITE the exact Decision
ids + titles — a bare verdict with no cited Decision evidence is invalid. Only INCOMPATIBLE blocks.
```

**Result:** each **incompatible** pair → **FLAG: contradiction, BLOCK-tier**, with the cited
Decision evidence. Each **complementary** pair → **NOT a conflict**; record it under the report's
**"Considered, not flagged → complementary shares"** section.

**Fallback — `capability:spawn-inline-checker` unavailable here** (mirrors loop's Gate-3 fallback): do **not**
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
| **`unverified` tier** (overlap: pinned script unavailable · contradiction: no checker capability) | **BLOCK** | the check never ran — strictly *less* informed than a known collision (D8, R7.4) |

**Overall verdict:**
- **`BLOCK`** — iff ≥1 block-tier finding (a contradiction OR an unordered overlap), **or any tier
  is labelled `unverified`**. [R4.1, R7.4]
- **`WARN`** — no block-tier findings, **no tier `unverified`**, and ≥1 warn-tier finding
  (redundancy and/or undeclared). [R4.2]
- **`OK`** — no findings **and** every tier actually ran.

**CRITICAL — an unordered overlap BLOCKS, it never warns (R4.3).** In a pre-batched / autopilot
path the human approval was given up front, so at Phase-2 there is **no human reading a WARN** — a
WARN there is an *unread annotation*. A known write-collision must therefore **hard-stop** the run,
not annotate it, or it would proceed to clobber unseen. This is the whole reason the unordered
overlap sits in the BLOCK tier and not the WARN tier.

**CRITICAL — an `unverified` tier BLOCKS, it never warns (D8, R7.4).** The caller contract admits
exactly `BLOCK | WARN | OK`, so "label the tier `unverified`" must still resolve to one of the three
or callers cannot branch. It resolves to **BLOCK**, not WARN, because an **uncomputable** collision
check is not safer than a known collision — it is strictly *less* informed, and a WARN would let a
set be built on an overlap (or contradiction) check that never ran. This holds regardless of who is
watching, and in practice a human always is: build-order calls this audit in **Phase 1 (Plan)** and
consumes the verdict at the **Phase-2 Approve**, while autopilot only ever resumes an
already-approved ledger — so a BLOCK here surfaces to a human at the Plan/Approve seam, exactly
where it should. There is therefore **no attendedness-sensitive branch** in this skill (D16: it
would be dead code). Degrading is not halting: the checker still writes its report and still only
*reports* — flag-only, Rule 1.

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
   specs it just generated, passing their **explicit paths** plus
   `report: specs/<set>/coherence-report.md` (R2.2), so the emitted set is independently
   contradiction-checked even on the standalone path and the caller knows exactly where to read the
   verdict back from. A **BLOCK** marks the set **not-done** and is surfaced to the initiating
   human — **never auto-resolved** (maker ≠ checker applied to the decomposer's own output).

In every path the checker reads the real generated `spec.md` files (their `## Declared Surface` /
`## Decisions`) — never decompose's reasoning or manifest. The two call sites are distinct
stages/inputs: intentional, idempotent defense-in-depth, not redundant work.

---

## Rules

1. **Flag-only — never push through the fence.** The checker WRITES `coherence-report.md` and
   nothing else. It **never** edits or rewrites a `spec.md` (R7.3). The human / calling skill
   resolves every finding; the checker never auto-resolves.
2. **Reads spec files only — and the line-1 marker is metadata, not content.** It reads real
   `spec.md` files (`## Declared Surface`, `## Decisions`, Requirements) — never decompose's
   reasoning, manifest, or task notes (maker ≠ checker, across the whole pipeline). A line-1
   `<!-- decompose-entry: <feature-id> @ sha256:<digest> -->` comment is **machine-owned metadata**:
   never spec content, never part of `## Decisions`, never evidence for a judged finding.
3. **Maker ≠ checker on contradiction.** The contradiction tier is run by a **separate checker
   subagent** — never the decomposer, and never handed the maker's reasoning. No checker capability →
   label the tier `unverified` (→ `BLOCK`, Rule 9); never silently pass it.
4. **Deterministic where possible — and overlap is a SCRIPT, not a judgement.** The glob
   set-intersection is computed by `capability:run-glob-overlap`
   — the same script decompose's pre-flight calls, so **when both invoke it** both skills return the
   same verdict for the same pair. Redundancy is maker-run; only contradiction is judged. Script
   unavailable → the tier is `unverified` (→ `BLOCK`, Rule 9); never fall back to inline reasoning or
   a relative path. **What this does not buy:** the script makes the algorithm testable, not enforced
   — nothing detects a skipped invocation, so the non-determinism relocates rather than disappears
   (T1 §1, "What extraction does NOT buy").
5. **Overlap is dependency-gated; contradiction is NOT — and the gate lives HERE, not in the
   script.** `glob-overlap.sh` computes the pure intersection only; this skill gates it against the
   **specs'** `depends_on` (decompose gates the same script's output against the **manifest's**).
   Overlap flags only an **unordered** pair (no `depends_on` path, direct or transitive); an ordered
   shared pair is legitimate and recorded "considered, not flagged". Contradiction runs over the
   **un-gated** shared surface.
6. **Severity-tiered, and an unordered overlap BLOCKS — never warns.** BLOCK = contradiction OR
   unordered overlap; WARN = redundancy or undeclared. In an unattended/pre-batched path a WARN is
   unread, so a known write-collision must hard-stop (R4.3).
7. **Undeclared degrades to WARN, never a hard block on absence** (D8) — emit the verbatim
   `surface undeclared; overlap unverifiable — declare to enable the check`; keep the checker usable
   on any spec set without forcing migration.
8. **Return a machine-readable verdict.** The overall `verdict: BLOCK | WARN | OK` lives in the
   report header; a caller reads it from the report file (deterministic file signal) and branches on
   it. The skill reuses the existing skills byte-unchanged — it only adds a call site for callers.
9. **A missing dependency DEGRADES, it never halts — and `unverified` resolves to `BLOCK`** (D8,
   D16, R7.4). No checker capability (tier 3), or no `glob-overlap.sh` / an exit `2` from it (tier 2) →
   label that tier `unverified`, treat its pairs as unresolved, write the report anyway, and yield
   `BLOCK`. Never a clean `OK` over a check that never ran, and never `WARN`: an uncomputable check
   is strictly less informed than a known collision. The skill still halts nothing — it reports
   (Rule 1).
10. **Honor a caller-named `report:` path.** When the invocation carries `report: <path>`, the
   report is written to exactly that path, taking precedence over the "audited set's directory if
   identifiable, else repo root" fallback (R2.3, D14).
