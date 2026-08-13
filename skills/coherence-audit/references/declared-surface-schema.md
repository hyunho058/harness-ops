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

### Provenance marker — line 1 of the spec, machine-owned  (D20)

Every `decompose`-generated `spec.md` carries a provenance marker as its **first line**,
ahead of the `# Spec:` heading. (These specs carry no frontmatter, so line 1 is the analogue
of a post-frontmatter placement.)

```markdown
<!-- decompose-entry: auth @ sha256:<64 lowercase hex chars> -->
# Spec: auth
```

| Token | Form | Meaning |
|-------|------|---------|
| `decompose-entry` marker | HTML comment on line 1 | Records **which** manifest entry produced this spec and **what that entry hashed to**, so a later run can tell "the SOURCE changed" apart from "the HUMAN edited the artifact" — a single two-way comparison cannot attribute a difference to one side. |

- **`decompose` writes it, never `specify`.** decompose stamps the marker immediately after
  the per-feature `specify` call returns, and only then flips that manifest entry's `state:`
  to `generated`. These are two files, so no single atomic write covers both; each write is
  individually atomic and **the order is fixed — stamp the spec first, flip the manifest
  second**. Both crash orders are then safe: a crash after stamping leaves `state: pending`,
  so the feature regenerates and is re-stamped; a crash after the flip cannot happen before
  the stamp exists.
- **The digest covers human-owned fields ONLY** — `feature-id`, `declared-surface`,
  `depends_on`, `accept-seed` — and **excludes `state:` and `pre-approved-batch:`**, which
  the machine flips on every normal run. Hashing those would make every entry read as
  "changed" on the next resume and turn a cheap resume into a full re-gate.
- **One shared implementation computes it on both sides:**
  `capability:run-entry-digest` (`entry-digest.sh <manifest> <feature-id>`),
  which prints the bare lowercase hex sha256. The stamping side and the verifying side call
  the same script, so — **when both invoke it** — a producer and a verifier cannot disagree
  about bytes nobody changed. Normalization (canonical field order, sorted glob and `depends_on` lists,
  collapsed whitespace, LF line endings) is documented in that script's header and is part of
  the contract. Note it does **not** path-normalize globs — a cosmetic `./src/x` → `src/x`
  edit does change the digest and reads as drift, deliberately erring toward more re-gating,
  never less.
- **It is machine-owned metadata, not spec content.** Every consumer must treat it as such:
  it is not part of any `## Decisions`, requirement, or prose that a reader or a judge
  evaluates; it is excluded from body preservation on an in-place structural merge; and it is
  re-stamped on every regeneration or merge.
- **An absent marker means a pre-marker spec, not a stalled run.** Sets generated before this
  contract carry no marker, so a resume compares only the structural fields the spec does
  carry (`declared-surface`, `depends_on`) against the entry — equal → unchanged, differ →
  changed — and **stamps the current digest either way**, so every later run is
  marker-driven. That one-time migration compare cannot see `accept-seed` drift; this is an
  accepted one-time blind spot, not a permanent one.

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
- `*` — **zero or more** chars **within one segment** (does not cross `/`). So `a*c`
  matches `ac` as well as `abc`.
- `?` — **exactly one** char within one segment.
- `**` — **zero or more whole segments** (crosses `/`); valid only as a full segment
  (`a/**`, `a/**/b`, `**/b`, `**`). Because zero segments is legal, `a/**` owns `a` itself.
  A `**` that is not a whole segment (`a/x**y/b`) is **invalid input**, not a literal.

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

### The normative implementation of this section (D7, D11, D13)

The prose above and the table are **implemented once**, at
`capability:run-glob-overlap`. Both callers —
`decompose`'s step-3 pre-flight and `coherence-audit`'s overlap tier — invoke that script
rather than judging overlap in prose, so **when both invoke it** the two cannot disagree about
the same pair. The table above ships as its test vectors, so a divergence between this prose
and the script surfaces as a **failing test** rather than silently — provided a human runs the
suite, since this repo has no CI. Run it with:

```
capability:run-portability-tests   # <harness-root>/skills/coherence-audit/scripts/run-tests.sh
```

**What extraction does NOT buy — enforcement (D7, Known Gap 1).** Single-sourcing the algorithm
makes it **testable**; it does **not** make it **enforced**. Nothing in this harness detects a
skipped invocation: "call the script" is itself an instruction an LLM may skip, exactly as
"compute this deterministically" was skipped before. Extraction therefore **relocates** the
non-determinism — from *how the intersection is computed* to *whether the script is run at all* —
rather than removing it, and it does so at the same (zero) enforcement. Every "cannot disagree"
claim on this page is conditional on both callers actually invoking the script. That gap is left
deliberately open: `.claude/hooks/` fire on tool events, not pipeline stages, so no hook can assert
"step 3 ran", and CI cannot invoke an LLM skill at all. Closing it is the job of behavioral evals,
which this change does not ship.

**Interface.** `glob-overlap.sh <surface-a-file> <surface-b-file>`, each file holding **one
bare glob per line** — one *surface* per file, matching this section's unit (overlap is
defined between glob SETS). Globs never pass through argv, so no shell can expand them.
Exit `0` = disjoint, stdout empty. Exit `1` = intersecting, stdout carries one
tab-separated `<globA>\t<globB>` line per intersecting pair (the evidence). Exit `2` =
usage or I/O error, diagnostics on stderr, stdout empty. The result space (`0`/`1`) is
deliberately disjoint from the error space (`2`) because **both** relation answers are
legitimate results — do not "fix" this into the `validate.sh` convention where any non-zero
means bad.

**Points this section formerly left open, now fixed** (each is pinned by a test vector):

| Case | Resolution |
|------|------------|
| Evidence form | The **normalized** glob, not the raw input line |
| Trailing `/` | Dropped — `src/auth/` ≡ `src/auth`, **not** `src/auth/**` |
| Malformed `**` (not a whole segment) | Exit `2` — it cannot yield a legitimate relation answer |
| A glob normalizing to an empty path (`/`, `.`, `./`) | Exit `2` |
| Empty surface (zero globs) | **Disjoint — exit `0`, not an error.** Absence is a WARN-tier signal owned by the consumer (see "Undeclared default"); the script must not swallow it |
| Bullet markers (`- `) | **NOT stripped.** Callers must hand the script bare globs — strip the manifest/spec bullet prefix first |
| Blank line, or a line whose first non-blank char is `#` | **Ignored**, so a vector/surface file may carry comments. Consequence: **a glob may not begin with `#`** — a literal `#notes/**` would be silently dropped rather than matched |
| Duplicate globs within one surface | Collapse to first occurrence after normalization; evidence never repeats a pair |
| Evidence ordering | A-major, then B — deterministic |
| A TAB inside a glob | Exit `2` — it would corrupt the tab-separated evidence |

**The script computes intersection ONLY.** Dependency-gating — *which* pairs a non-empty
intersection is applied to — contains no shared code and stays in each caller, because the
callers legitimately differ: `decompose` gates against the **manifest's** `depends_on`,
`coherence-audit` against the **specs'**.

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
### session-core
- declared-surface:
  - src/session/**
- depends_on: []
- accept-seed: Sessions persist across requests and expire on logout.
- pre-approved-batch: no
- state: pending

### auth
- declared-surface:
  - src/auth/**
  - app.py
- depends_on: [session-core]
- accept-seed: A user can log in and out with a persisted session.
- pre-approved-batch: no
- state: pending
```

### Per-feature field list (the `{...}` tuple, R1.1)

`{ feature-id, declared-surface (globs), depends_on, accept-seed }` — plus the
`pre-approved-batch` line of §3 and the `state:` line below. Mapping to downstream artifacts:

| Manifest field | Flows to |
|----------------|----------|
| `### <feature-id>` (heading) | the spec's `feature-id:` and `specs/<feature-id>/spec.md` dir |
| `declared-surface:` (globs) | copied **verbatim** into the spec's `## Declared Surface` → `declared-surface:` list |
| `depends_on:` | the spec's `depends_on:` AND build-order's ledger `depends_on:` (§4) |
| `accept-seed:` | seeds the spec's R0 acceptance sub-requirement AND build-order's ledger `accept:` field |
| `state:` | nothing downstream — decompose's own resume ledger (below) |

### Ownership: exactly two fields are machine-written  (D12, D19)

The manifest is the single object the **human** approves, and a resume makes the machine a
writer to it. That is safe only because the split is explicit:

| Written by | Fields |
|------------|--------|
| **Human only** | the feature set itself, `declared-surface:`, `depends_on:`, `accept-seed:`, `## Shared Decisions` — a resume **never** changes these |
| **Machine only** | `state:` and `pre-approved-batch:` — and nothing else |

**`state:` — decompose's per-feature resume ledger.** Exactly two values:

| Value | Meaning |
|-------|---------|
| `pending` | No trustworthy `spec.md` exists for this feature yet. Initialized `pending` when the manifest is written, **before any spec is generated**. |
| `generated` | `specify` returned successfully for this feature **and** the D20 marker has been stamped. |

- The flip to `generated` happens **only after** the per-feature `specify` call returns —
  never before. That write timing is what makes a crash mid-generation safe: a torn or
  missing `spec.md` is still `pending`, so a resume regenerates it rather than trusting it.
- **Every manifest rewrite is atomic** (temp file in the same directory + rename), so no
  reader can observe a torn manifest and no human can approve one.
- An **in-place structural merge** runs against a feature that is already `generated`, and
  `state:` deliberately does **not** mark it: leaving it `generated` would let a crash
  mid-merge strand a torn `spec.md` that the next resume trusts and skips, while resetting it
  to `pending` would mean "no body to preserve" and trigger the full regeneration the merge
  exists to avoid. The protection is atomicity instead — the merge writes `spec.md` atomically
  too, so the file is either wholly pre-merge or wholly post-merge and `generated` stays
  truthful either way. (This is why the vocabulary is two values and not
  `pending`/`running`/`generated`/`merging`: a `running` or `merging` state cannot be written
  durably around a synchronous call without a second flush, and atomicity solves the same
  problem without adding a state every reader must learn.)
- **Legacy manifests written before `state:` existed** are migrated by one-time inference on
  the next resume: a feature whose `spec.md` exists is `generated`, otherwise `pending`, and
  the field is then written.
- The line is **additive and name-keyed**: `specify mode: batch` looks up only
  `pre-approved-batch:` plus the surface fields, and `build-order` reads only `depends_on`.
  Neither validates the manifest against a fixed schema, so neither is affected.

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

**The flip runs in BOTH directions.** `no` → `yes` on an explicit human Approve, as above —
and on a **resume**, the machine also resets it **`yes` → `no`** for any entry that was
**changed or added** since the last run. Without that reset, a changed entry would still
carry `yes` from the original gate and `specify mode: batch` would bypass its prompts for a
partition **no human ever approved**. The reset is therefore what keeps the one-way human
guarantee true across re-entry, not a weakening of it:

| Direction | Written by | When |
|-----------|------------|------|
| `no` → `yes` | decompose | The human explicitly Approves the partition gate |
| `yes` → `no` | decompose | A resume detects that entry changed (D20 digest differs), or the entry is new |

Entries that did **not** change keep `yes` and are not re-asked — their original approval
still covers them, which is what keeps a resume cheap. An **Abort** at the scoped re-gate
leaves a changed entry at `pre-approved-batch: no` while keeping `state: generated`, so the
existing spec body is still there to preserve on the next attempt.

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
| `pre-approved-batch: yes\|no` (line) | manifest entry | decompose — **machine-written in BOTH directions**: `no`→`yes` post-gate, `yes`→`no` on resume for a changed or added entry (§3) | specify (bypass gate, D5) |
| `state: pending\|generated` (line) | manifest entry | decompose — machine-written (§2) | decompose's own resume ledger; **no downstream consumer** |
| `<!-- decompose-entry: <feature-id> @ sha256:<digest> -->` | **line 1** of each generated `spec.md` | decompose — machine-written, stamped after `specify` returns (§1) | decompose's resume (drift attribution). coherence-audit must treat it as **metadata, never as spec content** |

**Machine-owned vs human-owned, at a glance.** Only three tokens in this whole contract are
written by the machine — `state:`, `pre-approved-batch:`, and the `decompose-entry` marker.
Everything else in a manifest is human-authored and a resume never rewrites it.
