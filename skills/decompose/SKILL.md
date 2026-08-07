---
name: decompose
argument-hint: "\"<one project goal>\" [set: <name>]"
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
| **resumable**: a re-invocation resolves *which set this is* and **continues** it | a fresh-start-every-time generator — it never re-proposes a partition over an existing set |

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
  never leave a torn manifest the human might approve. **Every LATER rewrite is atomic too** (temp
  file in the SAME directory + rename): every `state:` flip and every `pre-approved-batch:` flip, so
  no reader can observe a torn manifest and no human can approve one (R4.4).
- It records the `- goal:` line verbatim — that line is the **resume key** step 0 matches against.
- Per feature it carries the `{ feature-id, declared-surface (globs), depends_on, accept-seed }`
  tuple + a `pre-approved-batch:` line (starts `no`) + a `state:` line (starts `pending`), and one
  top-level `## Shared Decisions` block every generated spec inherits verbatim.
- **EXACTLY TWO fields are machine-written: `state:` and `pre-approved-batch:`** — the latter in
  **both** directions (`no` → `yes` at the gate, `yes` → `no` on a resume for a changed or added
  entry) — **and nothing else**. The feature set, the declared surfaces, the `depends_on` edges, the
  `accept-seed`s and the shared decisions are changed **only ever by a human**; a resume never
  rewrites them (T1 §2, "Ownership: exactly two fields are machine-written").

---

## The pipeline

Six steps, preceded by **step 0** — resolving *which set this is*, which decides whether this run is
a fresh partition or a **resume**. The judgment is concentrated entirely at step 4; everything before
it is preparation, everything after it is mechanical reuse + an independent check.

### 0. Resolve WHICH set this is — BEFORE deriving a new `<set>`  (R3.1, R3.2, R3.3, R9.1, D18)

decompose has **no bare form**: its signature always carries a goal, and `<set>` is a kebab name
derived from that goal *text*. So a **rephrased goal derives a DIFFERENT `<set>`**, silently misses
the existing manifest, and generates a second overlapping set — the exact failure this skill exists
to prevent. Resolve set identity **first**: derive no `<set>`, write no manifest, and generate no
spec until it is resolved.

**1. An explicit `set: <name>` short-circuits the scan**  (R3.2). If the invocation carries the
token `set: <name>`, use `specs/<name>/partition-manifest.md` and **do NOT scan**. The token is in
the `argument-hint`, and it is spelled like every other named cross-skill token here (`mode: batch`,
`report:`). If that manifest does not exist, this is a **fresh** run under that set name.

**2. Otherwise SCAN before deriving**  (R3.1). `Glob specs/*/partition-manifest.md`, read each
candidate's top-level `- goal:` line, and compare it to the goal just passed. Cover **all four**
branches — no case may fall between the rules (R3.3):

| Found | decompose does |
|-------|----------------|
| **zero** manifests | **FRESH RUN** — derive a new `<set>` and continue at step 1 |
| exactly **one** whose `goal:` matches | **RESUME it** — go to **Resume** below; do **not** propose a new partition |
| several found, **NONE** matching | **ASK the human which set this is.** Never treat this as fresh. |
| several found, **MORE THAN ONE** matching | **ASK the human which set this is.** |

```
AskUserQuestion(
  question: "Which spec set does this goal continue? <N> partition manifests exist under specs/.",
  options: [
    { label: "<set-a>",     description: "goal: <that manifest's recorded goal>" },
    { label: "<set-b>",     description: "goal: <that manifest's recorded goal>" },
    { label: "New set",     description: "None of these — start a fresh partition for this goal" }
  ]
)
```

- **"Several present, none matching" is NOT a fresh run.** Starting a second overlapping set is the
  failure being prevented, and a human can legitimately re-type the same goal in different words.
- **Generate NOTHING until the question is answered.** Asking is always reachable: `AskUserQuestion`
  is in `allowed-tools` and no unattended caller invokes decompose.
- **Be honest that this match is a HEURISTIC, not a computation.** There is no deterministic set key
  — comparing a recorded `goal:` to a re-typed one is a judgement. That is why anything ambiguous
  routes to the human: the failure mode is **one extra question**, never a duplicated set.

**3. A malformed or unreadable manifest STOPS the run**  (R9.1, D21). Once a set is resolved (by
`set:` or by the scan), parse its manifest fully. If it cannot be parsed into feature entries — the
`## Features` block is missing, an entry is truncated, the file is unreadable — **stop and report the
parse error. Generate nothing; flip no `state:` and no `pre-approved-batch:`.**

- This is **distinct from the LEGACY manifest** the migration branch handles (R5.7): legacy means
  *parses fine, lacks `state:`*; malformed means *does not parse at all*.
- Never treat it as an empty set. "No entries parsed" and "no features" are indistinguishable
  outcomes with **opposite** meanings, so an unusable input is never treated as an empty one — the
  same posture as step 3's hard-fail.

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

### 2. Write the manifest — atomically  (R1.1, R4.1, R4.4)

Write `specs/<set>/partition-manifest.md` per the template, **atomically (temp + rename)**, with every
feature's `pre-approved-batch: no` **and every feature's `state: pending`**:

```bash
mkdir -p "specs/<set>"
# write the full manifest to a temp file in the SAME directory, then atomically rename:
#   ...write specs/<set>/.partition-manifest.md.tmp ...
mv "specs/<set>/.partition-manifest.md.tmp" "specs/<set>/partition-manifest.md"
```

The manifest is the single source the human approves and that batch-mode specify consumes per feature.
It does **not** generate any `spec.md` yet.

- **`state: pending` on EVERY entry, written now — before any spec exists**  (R4.1). `state:` is
  decompose's own per-feature resume ledger, two values only: `pending` | `generated`. Nothing
  downstream reads it (T1 §2); it exists so a resume can tell "already generated" from "never
  generated" without trusting the filesystem.
- **Write the `- goal:` line verbatim.** Step 0's resume scan matches on it; a goal that is
  paraphrased into the manifest makes the set harder to find later.
- **Every subsequent rewrite of this file is atomic too**  (R4.4) — every `state:` flip and every
  `pre-approved-batch:` flip goes to a temp file **in the same directory** and is renamed into
  place, so no reader can observe a torn manifest and no human can approve one.

### 3. Deterministic overlap PRE-FLIGHT — the SHARED script, NOT a skill call  (R1.2, D10, R7.1)

Before spending tokens generating N specs, fail fast on a **self-inflicted overlap**. The glob
set-intersection is **never judged in prose** — it is computed by the ONE shared implementation that
both this pre-flight and coherence-audit's overlap tier call, so — **when both invoke it** — the two
cannot disagree about the same pair (T1 §1, "The normative implementation of this section"):

```bash
# one surface file per feature — BARE globs, ONE PER LINE, `- ` bullet STRIPPED:
#   ...write "$TMP/<feature-a>.globs" and "$TMP/<feature-b>.globs" from each feature's
#      manifest `declared-surface:` list — globs only, no heading, no `declared-surface:` line...
"${CLAUDE_PLUGIN_ROOT}/skills/coherence-audit/scripts/glob-overlap.sh" \
  "$TMP/<feature-a>.globs" "$TMP/<feature-b>.globs"
# capture $? — 0 = disjoint · 1 = intersecting (evidence on stdout) · 2 = usage/IO error
```

Run it **once per feature pair**, over the manifest's own `declared-surface:` lists:

1. **Build the two surface files.** Strip the `- ` bullet prefix — the script does **not** strip it and
   would take `- src/auth/**` as a literal glob. Globs never travel through argv, so no shell can
   expand one against the real filesystem.
2. **Gate on the dependency graph — the gating is DECOMPOSE's, not the script's.** Build the feature
   graph from the manifest's `depends_on`. A pair is **ordered** iff a `depends_on` path exists either
   way (direct **or transitive**); else **unordered**. The script computes the pure intersection only
   and knows nothing about edges (T1 §1: "The script computes intersection ONLY").
3. **Branch on the EXIT STATUS**, never on parsed prose. `1` is a legitimate **result**, not a
   failure — capture `$?` explicitly; never run the call under `set -e` or chain it with `&&`.

| exit | means | decompose does |
|------|-------|----------------|
| `0` | disjoint (stdout empty) | pair is clean — continue. An **empty** surface exits `0` by contract; absence is a WARN-tier signal the *checker* owns at step 6, never a pre-flight failure. |
| `1` | intersecting; stdout = one `<globA>\t<globB>` TAB-separated line per pair | **UNORDERED → FAIL FAST**. **ORDERED → legitimate**, not a failure. |
| `2` | usage / IO error (malformed `**`, unreadable path, a TAB inside a glob) | **STOP** — an *uncomputed* check is not a passing one. Report the stderr diagnostic; fix the manifest and re-run. |

- **UNORDERED + exit 1 → FAIL FAST**: surface the offending `(feature-A, feature-B)` **and the
  script's stdout verbatim** — those `(globA, globB)` pairs are the evidence (the **normalized** globs)
  — and STOP before generating any spec. Revise the partition (step 1) and re-run.
- **ORDERED + exit 1 is legitimate** (B extends A's surface *after* A) — not a failure (mirrors the
  overlap tier's dependency-gating, R2.3).

**The pre-flight ALWAYS re-runs — on a fresh run AND on EVERY resume.**  (R3.4, D19)

It runs over the manifest **as it currently stands**, **whether or not the partition changed**, and
**before any spec is generated or merged**. It is cheap and deterministic, and the human may have
edited the partition between runs — an unordered collision introduced by that edit must be caught
before anything derives from it. Never skip it because specs are already on disk, and never skip it
because the classification found no change.

**Script unavailable → decompose HARD-FAILS. There is no fallback.**  (R7.3, D8, D22)

If the script is **missing**, **not executable**, or `${CLAUDE_PLUGIN_ROOT}` **does not resolve**
(plausible on the plain `.claude/skills/` stub-symlink path, where the skill is reached through a
symlink rather than as a loaded plugin), step 3 **stops the run**: **no *new* spec is generated and
no pipeline state is advanced** — on a resume, (e)'s one-time legacy normalization may already have
written derived `state:` lines and equal-case stamps, which are disk-derived and idempotent — and the
reason is reported to the human.

- **NEVER fall back to inline LLM reasoning.** That silently reintroduces the exact non-determinism the
  script exists to remove, while still *reading* like a completed pre-flight.
- **NEVER fall back to a relative path.** A skill's working directory is the user's repo root, so a
  relative path resolves there and could match an unrelated file.

This is deliberately **stricter than `coherence-audit`**, which degrades to an `unverified` overlap
tier instead of halting. The asymmetry is the callers': decompose is about to **write N files** and can
cheaply refuse; coherence-audit only writes a report, and a report that honestly says "unverified" is
more useful than no report at all.

> **A half-generated set cannot be audited while the script is missing — that is INTENDED.**  (R9.2, D21)
> The pre-flight re-runs over the manifest as it currently stands on **every** run, including a resume,
> so an interrupted set cannot reach step 6 — *even to audit the specs that already exist* — until the
> script is restored. Do **not** "fix" this by letting the pre-flight be skipped when specs are already
> on disk: the pre-flight guards the partition **every subsequent step derives from**, and auditing a
> partial set against a partition whose disjointness was never computed yields a verdict that means
> nothing.

This pre-flight makes **NO contradiction claim** — the manifest carries no per-feature `## Decisions`
yet, so contradiction is *structurally undetectable* until the specs exist. It is **decompose's own
gating over the manifest it just wrote**, and the shared script is a plain Bash helper — NOT a
`coherence-audit` skill call — so it does **not** violate coherence-audit's "reads spec files only"
contract. (The real cross-spec contradiction check happens at step 6, on the generated spec FILES.)

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

- **Approve** → proceed to step 5. Flip `pre-approved-batch: no` → `yes` in the manifest (atomic
  rewrite) for **every** feature just presented — on a fresh run that is all of them; on a scoped
  re-gate it is exactly the entries presented and no others. This is the specify-batch pre-approval
  line (T1 §3), written ONLY now, after the human approved.
- **Revise** → apply the corrections to the partition, re-write the manifest (step 2), re-run the
  pre-flight (step 3), re-present. Loop until Approve.
- **Abort** → stop. Generate nothing.

**Proceed ONLY on Approve.** No spec is generated, and no `pre-approved-batch` flips to `yes`,
otherwise.

> **On a RESUME this gate RE-FIRES, scoped to the changed and added entries only** — and those
> entries first have `pre-approved-batch` machine-reset **`yes` → `no`**, which is what keeps the
> guarantee above true across re-entry (Rule 3). Unchanged entries keep their `yes` and are **not**
> re-asked. See **Resume → c** below.

### 5. Drive specify in batch mode — per feature  (R1.4, D5, R2.1, R3.6, R4.2, R5.1)

For each feature in the approved manifest (topological order) whose entry reads **`state: pending`**
**AND** **`pre-approved-batch: yes`**, drive `specify` in batch mode. Pass the **exact T1 §3 tokens**:
the invocation marker `mode: batch` plus the feature + manifest entry that now carries
`pre-approved-batch: yes` (the bypass fires only with BOTH present):

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

**Never invoke specify for an entry reading `pre-approved-batch: no`**  (R3.6) — that entry is
awaiting the (re-)gate, so its bypass cannot fire and generating for it would produce a spec from a
partition no human approved.

**After EACH specify call returns: STAMP the spec, THEN flip the manifest — in that ORDER.**
(R4.2, R5.1, D12, D20)

```bash
# 1. STAMP FIRST — compute the entry digest with the ONE shared helper; never hand-roll the hash:
digest=$("${CLAUDE_PLUGIN_ROOT}/skills/coherence-audit/scripts/entry-digest.sh" \
           "specs/<set>/partition-manifest.md" "<feature-id>")   # bare lowercase hex sha256, exit 0
# exit 2 = usage / IO / feature-not-found → STOP; do not stamp and do not flip.
#    ...write specs/<feature-id>/.spec.md.tmp = the marker line, then the existing file verbatim...
mv "specs/<feature-id>/.spec.md.tmp" "specs/<feature-id>/spec.md"

# 2. THEN flip that entry `state: pending` → `state: generated` in the manifest (atomic temp+rename).
```

The marker is **line 1** of the spec, ahead of the `# Spec:` heading (these specs carry no
frontmatter, so line 1 is the analogue of a post-frontmatter placement):

```markdown
<!-- decompose-entry: auth @ sha256:<64 lowercase hex chars> -->
# Spec: auth
```

- **decompose stamps it — NEVER specify.** specify writes the spec *body* and must not change; the
  marker is machine-owned metadata, not spec content (T1 §1, "Provenance marker").
- **The ORDER is what makes both crash orders safe.** These are two files, so no single atomic write
  covers both; each write is individually atomic. Crash **after stamping, before the flip** → the
  entry still reads `pending`, so the feature is regenerated and re-stamped (R4.3 — a torn or missing
  `spec.md` is never trusted). Crash **after the flip** cannot happen before the stamp exists.
- **The flip happens ONLY after specify returns successfully** (R4.2) — never before, never
  optimistically.

Collect the generated path `specs/<feature-id>/spec.md` for each feature — that resolved set is the
input to step 6. On a **resume**, step 6's input is **every** feature in the current manifest —
regenerated, merged and unchanged alike — and **never** an orphan (see Resume → f).

### 6. decompose-end coherence-audit — maker ≠ checker on decompose's OWN output  (R1.5, D10)

As the **FINAL** step, hand the just-generated spec FILES to the independent checker. decompose is the
maker; `coherence-audit` is a *separate* judge — it reads the spec files only (never decompose's
reasoning or the manifest), so the emitted set is independently contradiction-checked **even on this
standalone path** (no build-order follow-on required):

**First, delete any file at the report path** — freshness is proven by construction, not inferred:

```bash
rm -f "specs/<set>/coherence-report.md"
```

**Then invoke the checker with the EXPLICIT generated spec paths and the named report path:**

```
Skill(skill="harness-ops:coherence-audit",
      args="specs/<feature-a>/spec.md specs/<feature-b>/spec.md ...
report: specs/<set>/coherence-report.md")
```

- **Explicit spec paths are the ONLY correct form here** (coherence-audit's "audit exactly these
  paths" form — the already-resolved set). Passing the `specs/<set>` dir is **NOT** an equivalent
  alternative: that form scans `<dir>/*/spec.md`, but `specs/<set>/` holds only the manifest, and the
  set directory and the `specs/<feature-id>/` directories are **siblings, not parent/child**. So
  `coherence-audit specs/<set>` matches **ZERO** specs and returns a false `OK` — a silent no-op of
  this maker ≠ checker gate. The **no-args** form is wrong too: it sweeps `specs/*/spec.md`, i.e.
  every unrelated spec in the repo, not this set.
- **`report: specs/<set>/coherence-report.md` names the read-back path** (R2.2). Without the token the
  report lands at "the audited set's directory if identifiable, else repo root" — and with scattered
  explicit spec paths **no set directory is identifiable**, so the location would be undefined. The
  named token takes precedence over that rule.

**Then require the report to EXIST before reading any `verdict:`**  (R2.4, R2.5, R2.6, D5, D15):

- The file was deleted moments ago, so its presence is what proves the verdict is **from this run**.
  Read the `verdict:` token **from `specs/<set>/coherence-report.md`** (a deterministic file signal —
  coherence-audit's return contract; its return message states the verdict as a secondary cross-check).
- **An ABSENT report means UNAUDITED — never "clean".** A crash between the delete and the audit's
  write leaves no file at all. Infer **no** passing verdict from a missing report, and none from a
  returned message alone; the set is unaudited and step 6 must run again.
- **A verdict is NEVER inherited across runs.** On a resume, step 6 re-runs **from scratch** — delete,
  re-audit, re-read — **regardless of the existing report's `input_ref`**. `input_ref` fingerprints
  *sorted feature-ids + spec paths*, and **neither changes when a spec is regenerated**, so a matching
  `input_ref` would certify exactly the stale report it was meant to catch. Accept the consequence:
  every resume re-runs the judged contradiction tier including its subagent. That is bounded — resumes
  happen at human-recovery speed, not in a hot loop.

Branch on the token:

| verdict | meaning | decompose does |
|---------|---------|----------------|
| `BLOCK` | ≥1 block-tier finding — a contradiction OR an unordered overlap — **OR a tier reported `unverified`**, i.e. the overlap or contradiction check could not run at all (an uncomputed check is strictly *less* informed than a known collision) | the set is **NOT done**. **Surface the finding to the initiating human and STOP** — never auto-resolve, never rewrite a spec. The human resolves **in the partition manifest** (reconcile the decisions there, or add the `depends_on` edge there), then re-runs. |
| `WARN`  | only redundancy / undeclared surfaces | report the warnings; the set stands (non-blocking). |
| `OK`    | no findings | the set is coherent for what is declared — done. |

**WHERE a `BLOCK` recovery edit goes: the partition manifest — not the spec.**  (R10.1, D10)
The reconciling edit — **including adding a `depends_on` edge** — is made in
`specs/<set>/partition-manifest.md`, because the manifest is the **partition's source of truth** and
what every generated spec copies from verbatim. Say so when surfacing the finding. Editing the spec
instead would put the human's fix on the side the machine corrects *back* toward the manifest, so it
would be silently reverted; editing the manifest makes it a **partition change**, which is what the
resume path treats it as.

A **block-tier** finding marks the set not-done and is surfaced to the human who initiated decompose —
**NEVER auto-resolved** ("never push through the fence"). This is maker ≠ checker applied to decompose's
OWN output: decompose authored the specs, a separate judge grades them, and decompose does not overrule
that judge.

---

## Resume — continuing an existing set  (R3.4–R3.7, R4.3, R5.1–R5.8, D4, D10, D17, D19, D20, D21)

Step 0 resolved this run onto an **existing** `specs/<set>/partition-manifest.md` — because the human
resolved a step-6 `BLOCK` and re-ran, or because a crash interrupted step 5, or because they edited
the partition. decompose then **CONTINUES that set**: step 1 is **skipped** (no new partition is
proposed) and the manifest's human-owned content is **never rewritten**. Only `state:` and
`pre-approved-batch:` are machine-written, here as everywhere.

Run these in order — **(e), then (a)–(c), all complete before any spec is written or merged**:

**e.** normalize a legacy set FIRST → **a.** classify every feature → **b.** re-run the step-3
pre-flight → **c.** re-fire the step-4 gate, scoped → **d.** generate `pending` / merge `changed` →
**f.** name any orphan → **g.** run step 6 from scratch.

> **(e) is lettered last below only because it is the legacy branch — it RUNS FIRST.** It is a
> normalizing pre-pass, not a post-step: after it, every entry carries a `state:` line and every spec
> either carries a line-1 marker or has been explicitly classified `changed`, which is exactly the
> precondition (a)'s table assumes. **Running (e) after (d) would let a hand-edited pre-marker entry
> reach (d)'s merge without passing (c)'s scoped re-gate** — generating against a partition no human
> re-approved (R3.5, R3.6, D19, Rule 3). Every set generated before this contract is pre-marker, so
> that is the **default** path, not an edge case.

### a. Classify — did the ENTRY change, per feature?  (R5.2, R5.3, D20)

Recompute each entry's digest with the **ONE shared helper**. Never hand-roll the hash: the stamping
side and the verifying side must run the same bytes through the same normalization, or they disagree
about an entry nobody edited.

```bash
digest=$("${CLAUDE_PLUGIN_ROOT}/skills/coherence-audit/scripts/entry-digest.sh" \
           "specs/<set>/partition-manifest.md" "<feature-id>")
# stdout = the bare lowercase hex sha256, nothing else · exit 0
# exit 2 = usage / IO / feature-not-found → STOP. An UNCOMPUTED comparison is not a matching one.
# `--canonical` as an optional FIRST flag prints the pre-hash text — for debugging a surprise drift.
```

Compare it to the digest carried in that spec's line-1 marker
`<!-- decompose-entry: <feature-id> @ sha256:<digest> -->`.

**Precondition — (e) has already run**, so every entry carries a `state:` line, and every spec on
disk either carries a marker or was classified `changed` by (e)'s structural compare. **Evaluate
TOP-DOWN — the first matching row wins**, so no feature can land in two classes:

| Case | Classification | Handled at |
|------|----------------|------------|
| `spec.md` on disk with **NO** manifest entry (the human removed the feature) | **orphan** | (f) — warn, never delete |
| entry present, **no `spec.md` on disk**, and `pre-approved-batch:` reads `no` or is absent (a hand-added entry no human gate ever covered) | **added** | (c) re-gate → (d) generate through specify |
| entry reads **`state: pending`** (approved earlier; generation never completed — R4.3) | **pending** | (d) — regenerate through specify; there is no body to preserve, and no re-gate is owed |
| spec still carries **NO marker** because (e) found a structural **difference** | **changed** | (c) re-gate → (d) in-place merge, which re-stamps |
| marker digest **EQUALS** the recomputed digest | **unchanged** | (d) — **left completely alone** |
| marker digest **DIFFERS** | **changed** | (c) re-gate → (d) in-place structural merge |
| **anything else** | **cannot occur once (e) has run** | **STOP and report** — an unclassifiable feature is never treated as unchanged |

- **Machine flips do NOT perturb the digest.** It hashes **only** `feature-id`, `declared-surface`,
  `depends_on`, `accept-seed`, and **excludes `state:` and `pre-approved-batch:`** — otherwise every
  entry would read "changed" on every resume and the cheap path would be unreachable.
- **An `accept-seed`-only edit still reads CHANGED.** That is deliberate — see the merge scope in (d).
- **`pending` vs `added` is the `pre-approved-batch:` line.** Both lack a `spec.md`; only `added`
  lacks an approval. A crash-interrupted feature already carries `yes` from the original gate, so it
  is regenerated without re-asking; a hand-added entry carries `no`, so it must pass (c) first.

### b. The pre-flight re-runs — ALWAYS  (R3.4)

Re-run **step 3** over the manifest as it currently stands, **whether or not (a) found any change**,
and **before any spec is generated or merged**. UNORDERED + exit 1 → fail fast exactly as on a fresh
run. Script unavailable → hard-fail exactly as on a fresh run — that a half-generated set then cannot
reach step 6 *even to audit the specs already on disk* is **INTENDED**, not a bug to route around
(step 3's callout, R9.2).

### c. The re-gate — step 4 re-fires, SCOPED  (R3.5, R3.6, R3.7, D19)

**Reset first, then ask.** For every **changed** and every **added** entry, machine-write
`pre-approved-batch: yes` → `no` (atomic manifest rewrite). **Unchanged entries keep `yes` and are
NOT re-asked** — their original approval still covers them, and that is what keeps a resume cheap.

**Why the reset is load-bearing, stated plainly:** without it, every entry still carries `yes` from
the ORIGINAL gate, so `specify mode: batch` would fire its bypass and generate for a partition **no
human ever approved** — a direct violation of decompose's own **Rule 3**. The reset does not weaken
the human-approval guarantee; it is what keeps that guarantee TRUE across re-entry.

Then re-present **only those entries** — with what changed in each — and re-fire the step-4
`AskUserQuestion`. It is a **real gate**, so it has all three outcomes:

| Outcome | decompose does |
|---------|----------------|
| **Approve** | flip the re-gated entries back `no` → `yes` (atomic) and proceed to (d). Generation for a changed/added entry happens **only** after this explicit Approve. |
| **Revise** | apply the human's corrections to the partition, re-write the manifest, **RE-RUN the pre-flight (b)**, re-present. Loop until Approve or Abort. |
| **Abort** | **generate nothing, merge nothing** — and do **not** touch `state:` (below). |

**Abort's state rule — it must NOT reset `state:` to `pending`**  (R3.7):

| Entry at Abort | Left as |
|----------------|---------|
| **changed**, whose `spec.md` exists | **`state: generated`** (kept) + `pre-approved-batch: no` |
| **added**, no spec on disk | `state: pending` + `pre-approved-batch: no` |

Resetting a changed entry to `pending` would tell the next resume there is **no body to preserve**,
so it would full-regenerate through specify and **destroy exactly the hand edits this machinery
exists to protect**. The spec is still on disk and still stamped — `generated` stays truthful, and
`pre-approved-batch: no` is what stops it being generated from until a human approves.

### d. Generate or merge — ONLY what needs it  (R5.4, R5.5, R5.6, D10, D17)

| Classification | Action |
|----------------|--------|
| **unchanged** | **NOTHING.** Not regenerated, not merged, not rewritten — so hand edits in it survive (R5.4). |
| **pending** / **added** | **Step 5**: `specify mode: batch` → stamp the marker → flip `state: generated`. specify is re-invoked here **precisely because there is no body to preserve**. |
| **changed** (its `spec.md` exists) | **In-place STRUCTURAL MERGE, performed by decompose ITSELF** — *not* by re-invoking specify (which would re-derive L2–L4 and append over the human's prose: regeneration wearing a merge's name). |

**The structural merge — "spec owns the skeleton, human owns the flesh."**  (R5.5, D17)

decompose rewrites **EXACTLY these four things** in `specs/<feature-id>/spec.md`, and nothing else:

1. **`## Declared Surface`** — `feature-id:`, `depends_on:`, `declared-surface:` re-copied
   **verbatim** from the manifest entry (T1 §1's exact tokens).
2. **The inherited `## Shared Decisions` / `SD<n>` block** at the top of the spec's `## Decisions` —
   re-copied **verbatim** from the manifest. The feature's own `D<n>` decisions below it are body.
3. **The `accept-seed`-derived R0 acceptance sub-requirement** — locate it by the **seeded text**
   (specify's convention places it at `#### R0.1`, but no contract pins that id, so never match on
   the heading id alone) — re-seeded from the
   entry's `accept-seed:`.
4. **The `decompose-entry` marker on line 1** — re-stamped with the freshly recomputed digest.

Everything else in the file is **body and is preserved byte-for-byte**. Write the merged file
**ATOMICALLY** (temp file in the same directory + rename), so a crash mid-merge leaves it wholly
pre-merge or wholly post-merge and `state: generated` stays truthful either way (T1 §2). Then
**report the divergence as a WARNING**, naming which of the four the merge corrected.

**The `accept-seed` → R0 projection is IN the merge scope — it is not an afterthought**  (R5.6).
`accept-seed` flows onward: into this R0 acceptance sub-requirement **and** into build-order's ledger
`accept:`. If the merge covered only the surface and the shared decisions, an `accept-seed`-only edit
would be **detected, re-gated, and then re-stamped as reconciled while the STALE R0 stayed on disk** —
after which build-order gates the build against an acceptance criterion the human already replaced.
So the R0 sub-requirement **seeded from `accept-seed` is machine-owned** and is corrected in the same
merge, named in the divergence warning. **Human elaboration elsewhere in R0, and every other
requirement, is body and is preserved.**

> **This does NOT violate Rule 7 ("never rewrites a spec").** Rule 7 is scoped to **never rewriting a
> spec to SILENCE a coherence finding**. A mechanical structural correction *toward the partition the
> human approved* is the **opposite** of suppressing a finding: it makes the spec match its approved
> source, the human's prose is preserved, the divergence is reported, and the independent step-6
> checker still grades the result. The two rules are not in tension — do not read them as such.

### e. Migration — normalize a legacy set FIRST, so an existing set can RESUME AT ALL  (R5.7, D20)

**This RUNS BEFORE (a)**, despite its letter — see the ordering note at the top of Resume. Every set
generated before this contract carries no marker, and a manifest written before `state:` existed
carries no `state:` line. A resume must neither stall on their absence **nor skip the re-gate because
of it**.

Two one-time inferences, each an atomic write:

- **Manifest entry with no `state:` line** → a feature whose `spec.md` exists is **`generated`**,
  otherwise **`pending`**; write the field (atomic rewrite). Do this **before** (a)'s table is
  evaluated — a legacy entry that reaches the table without a `state:` line matches no row.
- **Spec with NO line-1 marker** → compare only the structural fields the spec *does* carry —
  `declared-surface:` and `depends_on:` in its `## Declared Surface` — against the manifest entry.
  **Skip any spec with no manifest entry at all — (f) owns those orphans**, and (f) runs later:
  - **Equal → the entry is `unchanged`.** Stamp the current digest now (`entry-digest.sh`, atomic
    write); (a) then classifies it `unchanged` on the marker it now carries. **`entry-digest.sh`
    exit 2 → STOP, same as in (a)** — an uncomputed digest is never a matching one.
  - **Differ → the entry is `changed`. Do NOT stamp here.** Leave it unstamped so it enters (c)'s
    scoped re-gate like any other changed entry; **(d)'s merge re-stamps it** once the human
    approves. Stamping a *differing* spec before (a) would make its digest match the entry, (a) would
    read it `unchanged`, and the re-gate would be silently skipped — merging against a partition no
    human re-approved (R3.5, R3.6, Rule 3).
  - **The equal case stamps here; the differ case stamps in (d)'s merge (R5.5)** — so a spec stays
    unmarked only while its re-gate is unresolved (an **Abort** at (c) leaves it unstamped, and the
    next resume simply repeats (e) for it: idempotent, not stuck). D20's "stamp either way" is
    satisfied **across the two paths**, not by stamping before the classification that depends on it
    — which would make the digest match, read `unchanged`, and skip the re-gate.
- **Accepted ONE-TIME blind spot:** the migration compare **cannot see `accept-seed` drift** — that
  field has no projection in `## Declared Surface`. It is one-time, not permanent: from the next run
  on, the stamped marker carries the full digest.
- This is the **legacy** branch. A manifest that does not parse at all is a different thing entirely
  and stops the run (step 0.3, R9.1).

### f. An orphaned spec of a REMOVED feature — warn, NEVER delete  (R5.8, D21)

A `specs/<feature-id>/spec.md` whose feature the human removed from the partition is **left on disk
with a warning — never deleted** (decompose does not delete a human's files), and it is **excluded
from step 6**, which audits only the current set's explicit spec paths.

**Name the orphan EXPLICITLY in the completion report, with the consequence.** build-order's **Plan**
can still reach that file through its `specs/*/spec.md` **glob fallback**, where its stale declared
surface can collide with the new partition — producing a **`BLOCK` at Plan on a set decompose just
certified `OK`**. Tell the human plainly: *"`specs/<feature-id>/spec.md` is no longer in the
partition — delete it or re-adopt it as a feature, or build-order's Plan may BLOCK on its stale
declared surface."* That is what makes the later BLOCK **anticipated rather than mysterious**.

### g. Step 6 runs from scratch — a verdict is NEVER inherited

Delete the report at the named path, re-audit the **current set's** explicit spec paths (every feature
in the manifest — regenerated, merged and unchanged alike; **never** an orphan), and re-read the
`verdict:` — exactly as on a first run, **regardless of any existing report's `input_ref`** (step 6
states why). maker ≠ checker is not weakened by a resume.

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
3. **ONE human gate; proceed only on Approve — and the machine RESETS that approval when the partition
   changes.** All cross-feature judgment concentrates at the partition gate. No spec is generated, and
   no `pre-approved-batch` flips to `yes`, without an explicit Approve. `pre-approved-batch` is
   **machine-written in BOTH directions**: on a **resume** decompose resets it **`yes` → `no`** for
   every **changed or added** entry and re-fires the gate scoped to those entries (unchanged entries
   keep `yes` and are not re-asked). The reset does **not** weaken the guarantee — it is what keeps it
   TRUE across re-entry, since without it an edited entry would still carry `yes` from the original
   gate and `specify mode: batch` would bypass its prompts for a partition no human ever approved.
4. **Every durable write is atomic** (temp file in the SAME directory + rename): the first manifest
   write, which happens **before** any spec is generated; **every later `state:` / `pre-approved-batch:`
   flip**; and the `spec.md` an in-place structural merge rewrites. No reader may observe a torn
   manifest, no human may approve one, and no resume may trust a torn spec.
5. **The pre-flight makes no contradiction claim.** It is decompose's own dependency-gating over the
   manifest (NOT a coherence-audit call); contradiction is undetectable until specs exist. The
   intersection itself is **computed by the shared `glob-overlap.sh`, never reasoned about in prose**,
   and if that script cannot be run decompose **hard-fails** — it never falls back to inline reasoning
   or to a relative path. **Be honest about what that buys:** single-sourcing makes the algorithm
   testable, not enforced. Nothing detects a skipped invocation, so the non-determinism moves from
   *how* the intersection is computed to *whether* this script is actually run — the gap is real and
   open (T1 §1, "What extraction does NOT buy").
6. **Maker ≠ checker.** decompose authors; `coherence-audit` (a separate judge) grades. decompose calls
   it at decompose-end and **branches on its verdict** — it never self-certifies its own output.
7. **Never auto-resolve a conflict — never push through the fence.** A block-tier finding is surfaced to
   the human and the set is marked not-done. decompose never rewrites a spec **to silence a finding** —
   that is the scope of this rule. The in-place **structural merge** (Resume → d) is therefore not an
   exception to it: it corrects machine-owned structure *toward the partition the human approved*,
   preserves the body, reports the divergence as a warning, and still hands the result to the
   independent step-6 checker. Correcting toward an approved source is the opposite of suppressing a
   finding; do not read the two as contradictory.
8. **Emit the exact T1 tokens.** `## Declared Surface` + `declared-surface:` + `depends_on:` in each spec
   (R2.1), the `## Shared Decisions` / `SD<n>` block + `pre-approved-batch:` + `state:` lines in the
   manifest, the `<!-- decompose-entry: <feature-id> @ sha256:<digest> -->` marker on **line 1** of each
   generated spec (stamped by decompose, never by specify), and the `mode: batch` marker on each specify
   call — bound to `skills/coherence-audit/references/declared-surface-schema.md`, never redefined.
9. **Reuse the existing skills byte-unchanged.** decompose only *calls* specify (batch) and
   coherence-audit; it alters neither, and touches neither loop, build-order, nor autopilot.
10. **A resume NEVER mutates human-approved partition content.** Exactly **two** manifest fields are
    machine-written — `state:` and `pre-approved-batch:` — and **nothing else**. The feature set, the
    declared surfaces, the `depends_on` edges, the `accept-seed`s and the shared decisions are changed
    **only ever by a human**. On re-entry decompose resolves WHICH set this is *before* deriving a new
    one (step 0), stops on a manifest it cannot parse, re-runs the pre-flight, re-gates what changed,
    regenerates only `pending` features, structurally merges only `changed` ones, and leaves unchanged
    specs untouched.
