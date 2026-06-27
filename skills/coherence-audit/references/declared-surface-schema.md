# declared-surface-schema.md — the spec-set coherence data contract

> The ONE shared schema that three skills bind to: `decompose` (the producer —
> WRITES it), `coherence-audit` (the consumer — READS it), and `specify` in
> `mode: batch` (which consumes the manifest per feature). It fixes three
> interlocking data shapes so the producer/consumer interface cannot drift.
> **This doc defines DATA + field semantics only.** The detection algorithm, the
> verdict tiering (D3/R4), and the report layout live in the consuming skills
> (`coherence-audit` = T2, `decompose` = T3); they are referenced here, never
> re-specified. Honor the spec's fence: the checker only ever FLAGS — it never
> rewrites a spec ("never push through the fence").

Three sub-contracts:
1. The **declared-surface section** a `spec.md` carries (§1 — D6, D8, R2.1/R2.2).
2. The **partition manifest** `decompose` writes before any spec exists (§2 — D10, R1.1).
3. The **specify `mode: batch` marker + per-feature pre-approval** (§3 — D5, R5.1).

The `depends_on` representation shared by all three (§4) is matched to build-order's
existing ledger field, not invented.

---

## 1. Declared-surface section — in each `spec.md`  (D6, D8, R2.1, R2.2)

Every `decompose`-emitted spec carries exactly ONE section that declares the files /
modules the feature **owns**, as repo-root-relative **path globs**.

### Heading + shape (exact tokens)

```markdown
## Declared Surface
- feature-id: auth
- depends_on: [session-core]
- declared-surface:
  - src/auth/**
  - app.py
```

Field semantics:

| Field | Form | Meaning |
|-------|------|---------|
| `feature-id` | kebab string | The feature's id; defaults to the spec's directory name (`specs/<feature-id>/spec.md`). It is the resolution key for `depends_on` edges. |
| `depends_on` | `[<feature-id>, ...]` (`[]` = root) | Feature-level edges. **Matched to build-order — see §4.** |
| `declared-surface` | bullet list of globs | The owned path globs. Copied **verbatim** from the feature's manifest entry (§2). |

- The section heading is **`## Declared Surface`** (Title Case). The machine-readable
  glob field is **`declared-surface:`** (kebab + colon). Both spellings are load-bearing:
  the heading is what the "declared vs undeclared" check (D8) keys on; the field is what
  the overlap check (R2.2) reads.

### Undeclared default (D8) — absence WARNS, never hard-blocks

A spec is **surface undeclared** iff it has **no `## Declared Surface` section** OR its
`declared-surface:` list is empty/absent. For such a spec the consumer emits the WARN
(verbatim string):

> `surface undeclared; overlap unverifiable — declare to enable the check`

Absence ≠ conflict: an undeclared surface is a WARN-tier signal only — `coherence-audit`
**never hard-blocks on absence alone** (D8). This keeps the checker usable on hand-written /
legacy spec sets without forcing migration. (A spec with no `## Declared Surface` section
also carries no machine-readable `depends_on`, so build-order treats it as a root — its
existing "infer from spec metadata if present, else root" path, unchanged.)

### Glob semantics — deterministic, set-intersectable (D6, R2.2)

Globs make overlap a **deterministic non-empty path/glob set-intersection** — not a judged
call. Same inputs → same verdict.

**Normalization.** Repo-root-relative POSIX path; no leading `/`, no `./`; collapse `//`.
A directory is owned by writing an explicit `/**` suffix (decompose always emits this) — a
bare path with no wildcard matches that one path only.

**Wildcards.**
- `*` — any run of chars **within one segment** (does not cross `/`).
- `?` — a single char within one segment.
- `**` — **zero or more whole segments** (crosses `/`); valid only as a full segment
  (`a/**`, `a/**/b`, `**/b`, `**`).

**Two globs OVERLAP** iff at least one concrete repo path is matched by BOTH (segment-wise
unification: literal≡literal; `*`/`?` unify one segment; `**` unifies zero-or-more segments
on the other side). **Two surfaces (glob SETS) overlap** iff ANY glob in set A overlaps ANY
glob in set B; the overlap evidence is the specific `(globA, globB)` pair(s).

| Glob A | Glob B | Overlap? | Why |
|--------|--------|----------|-----|
| `app.py` | `app.py` | yes | identical |
| `src/auth/**` | `src/auth/login.py` | yes | B is under A's subtree |
| `src/**` | `src/auth/**` | yes | A's subtree contains B's |
| `src/**/util.py` | `src/auth/util.py` | yes | `**` → `auth` |
| `src/auth/**` | `src/api/**` | no | disjoint subtrees |
| `src/*.py` | `src/auth/login.py` | no | `*` is one segment; B has an extra segment |
| `app.py` | `app.js` | no | distinct literals |

### How the consumer interprets this section (informative — logic is T2)

- **Overlap tier is dependency-gated (D2, R2.3).** A non-empty surface intersection between
  features A and B is flagged **only when A and B are UNORDERED** — i.e. there is no
  `depends_on` path (direct or transitive) between them. An ordered pair sharing a surface
  is legitimate (B extends A's file *after* A is done) and is **not** flagged for overlap.
- **Contradiction is NOT gated (D7, D2-scope).** The dependency-gating above applies to the
  overlap / redundancy tier ONLY. Contradiction detection runs over the **un-gated** shared
  surface — ordering makes write-*timing* deterministic but never makes two opposite
  `## Decisions` coherent, so an ordered pair can still contradict. Contradiction reads each
  spec's `## Decisions` (title + rationale + rejected-alternatives), not this section.
- The verdict tiering (which signal BLOCKs vs WARNs) is owned by `coherence-audit` (D3/R4);
  this schema only fixes the fields those rules read.

---

## 2. Partition manifest — written by `decompose`  (D10, R1.1)

The manifest is **decompose's load-bearing artifact**: the single human-approval object AND
the per-feature input `specify mode: batch` consumes. It is written **atomically (temp file +
rename)** and **before any `spec.md` is generated**.

- **Path (convention):** `specs/<set>/partition-manifest.md` (`<set>` = the kebab batch name
  decompose derives from the goal; sibling-in-spirit to build-order's `build_order.md`).

### Shape (exact tokens)

```markdown
# partition-manifest.md — <set name>
- generated_at: <stamp>
- goal: <the one project goal this partition decomposes>

## Shared Decisions
### SD1: <cross-cutting tech/architecture choice, made ONCE for the whole set>
- **Status**: resolved
- **Rationale**: <why, including rejected alternatives>

## Features  (ordered — a dependency appears before its dependents)
### auth
- declared-surface:
  - src/auth/**
  - app.py
- depends_on: [session-core]
- accept-seed: A user can log in and out with a persisted session.
- pre-approved-batch: no

### session-core
- declared-surface:
  - src/session/**
- depends_on: []
- accept-seed: Sessions persist across requests and expire on logout.
- pre-approved-batch: no
```

### Per-feature field list (the `{...}` tuple, R1.1)

`{ feature-id, declared-surface (globs), depends_on, accept-seed }` — plus the
`pre-approved-batch` line of §3. Mapping to downstream artifacts:

| Manifest field | Flows to |
|----------------|----------|
| `### <feature-id>` (heading) | the spec's `feature-id:` and `specs/<feature-id>/spec.md` dir |
| `declared-surface:` (globs) | copied **verbatim** into the spec's `## Declared Surface` → `declared-surface:` list |
| `depends_on:` | the spec's `depends_on:` AND build-order's ledger `depends_on:` (§4) |
| `accept-seed:` | seeds the spec's R0 acceptance sub-requirement AND build-order's ledger `accept:` field |

### Shared-decisions block (exact heading: `## Shared Decisions`)

The cross-cutting tech/architecture choices made ONCE for the whole set. **Every generated
spec inherits this block verbatim** as the top of its own `## Decisions`, under the same
`SD<n>` ids, followed by that feature's local `D<n>` decisions. (Informative for the
contradiction tier: identical inherited `SD<n>` entries are shared common ground — not a
conflict; only divergent feature-local `D<n>` decisions on a shared surface are contradiction
candidates per D7.)

### Decompose's own pre-flight (R1.2) — not a skill call

Before the human partition gate (R1.3), decompose runs its OWN deterministic glob-collision
check over the manifest (the §1 set-intersection logic, applied to the `declared-surface:`
lists) to fail fast on a self-inflicted **overlap** before spending tokens generating N specs.
It makes **no contradiction claim** here — the manifest carries no per-feature `## Decisions`
yet, so contradiction is structurally undetectable until the specs exist. This pre-flight is
decompose's internal logic; it does NOT violate `coherence-audit`'s "reads spec files only"
contract.

---

## 3. specify `mode: batch` — additive bypass mirroring loop  (D5, R5.1)

`specify` gains ONE additive, opt-in batch path that mirrors loop's
`pre-approved-unattended` precedent (`skills/loop/SKILL.md:231-239, 438`). Faithfully
mirroring loop's **marker-AND-line** rule, the bypass fires only when BOTH are present:

- **Invocation marker (exact string):** `mode: batch`
  — passed by `decompose` when it invokes specify for a feature.
- **Per-feature pre-approval line (exact string):** `pre-approved-batch: yes`
  — written by `decompose` into that feature's manifest entry (§2), flipped from `no` to
  `yes` ONLY after the human approves the partition gate (R1.3). It is the specify analogue
  of loop's `pre-approved-unattended: yes`.

Bypass condition (mirrors loop:233-236): specify skips its interactive prompts **iff** the
invocation carries `mode: batch` **AND** the feature's manifest entry carries
`pre-approved-batch: yes`. A bare `/specify "goal"` (no marker) is **byte-unchanged** (R5.3).

### What it SKIPS vs does NOT skip (R5.1, R5.2 — mirrors loop's "approval prompt only")

| Skipped (interactive approval prompts ONLY) | NOT skipped (every gate + derivation still runs) |
|---------------------------------------------|--------------------------------------------------|
| L0 mirror confirmation prompt | L1 codebase research |
| L2 decisions `AskUserQuestion` (Approve/Revise/Abort) | L2 / L3 / L4 **derivation** from the partition |
| L3 requirements `AskUserQuestion` | the per-spec **L2-reviewer** subagent (within-spec maker ≠ checker: complexity / coverage / vague-decision / cross-decision-tension / steelman) |
| L4 tasks `AskUserQuestion` | self-validation at every layer transition |

The bypass skips **only the human `AskUserQuestion` approval prompts** — the human already
owns the bar via the ONE partition gate (R1.3). `coherence-audit` is a *cross*-spec checker
and does **not** substitute for the *within*-spec L2-reviewer, so each generated spec keeps
its own adversarial review (D5 gate-preservation, R5.2). Batch mode's deliverable is the
written `spec.md`; it does not trigger L4's execution handoff (the caller — decompose, then
build-order — owns execution).

---

## 4. `depends_on` representation — MATCHED to build-order  (cross-cutting)

The feature-level `depends_on` used by §1 (spec) and §2 (manifest) is **matched to
build-order's existing ledger field**, the one build-order already consumes for topological
ordering (`skills/build-order/SKILL.md:82`, `references/build_order-template.md:15,22`):

```
- depends_on: [<feature-id>, ...]   # list of feature-ids; [] = a root
```

- **Form:** a dash-prefixed `depends_on:` field whose value is a bracketed list of
  **feature-ids** (the same ids that head manifest `### <feature-id>` blocks and equal each
  spec's directory name). `[]` = a root.
- **Placement:** a field inside the `## Declared Surface` section of `spec.md` (§1) and inside
  each manifest `### <feature-id>` block (§2). build-order's "infer each feature's
  `depends_on` from its spec metadata if present, else treat as root" reads it from there
  unchanged.
- **Ordering / cycles:** edges are transitive; build-order topologically orders so every
  `depends_on` precedes its dependents and **refuses to start on a cycle** — that logic stays
  in build-order; this contract only fixes the field's spelling and values.

**Not this field (different scope, no conflict):** specify's *task-level*
`- **Depends on**: T1, T2` in a spec's `## Tasks` section
(`skills/specify/references/L4-tasks.md:85-102`) orders *tasks within one spec* by task-id.
The §1/§2 `depends_on` orders *features across specs* by feature-id. Distinct granularity,
distinct spelling (`depends_on:` list vs `**Depends on**:` bold) — intentionally kept apart.

---

## Quick field reference

| Token | Where | Producer | Consumers |
|-------|-------|----------|-----------|
| `## Declared Surface` (heading) | each `spec.md` | decompose | coherence-audit (declared vs undeclared, D8) |
| `declared-surface:` (globs) | spec.md + manifest | decompose | coherence-audit (overlap, R2.2) |
| `depends_on: [<feature-id>, ...]` | spec.md + manifest | decompose | coherence-audit (overlap-gate D2) + build-order (topo order) |
| `accept-seed:` | manifest | decompose | spec R0 + build-order `accept:` |
| `## Shared Decisions` / `SD<n>` | manifest → every spec's `## Decisions` | decompose | coherence-audit (contradiction common-ground, D7) |
| `mode: batch` (marker) | specify invocation | decompose | specify (bypass gate, D5) |
| `pre-approved-batch: yes` (line) | manifest entry | decompose (post-gate) | specify (bypass gate, D5) |
