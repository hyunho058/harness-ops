# partition-manifest.md — <set name>

> Written by `decompose` (T3) as its **load-bearing artifact**: the single
> human-approval object AND the per-feature input `specify mode: batch` consumes.
> The shape below is fixed by the T1 contract
> (`skills/coherence-audit/references/declared-surface-schema.md` §2) — emit EXACTLY
> these tokens; the producer (decompose), the consumer (coherence-audit), and
> specify-batch all bind to them, so the shape must not drift.
>
> **Written atomically (temp file + rename) and BEFORE any `spec.md` is generated.**
> Path convention: `specs/<set>/partition-manifest.md` (`<set>` = the kebab batch
> name decompose derives from the goal; sibling-in-spirit to build-order's
> `build_order.md`). Each feature's `pre-approved-batch:` starts `no` and is flipped
> to `yes` ONLY after the human approves the ONE partition gate (R1.3) — it is the
> specify analogue of loop's `pre-approved-unattended: yes`. On a **resume** the machine
> also flips it back **`yes` → `no`** for any entry that changed or was added, so a
> partition no human approved can never reach `specify mode: batch` (see Notes).
>
> **Exactly two fields are machine-written — `pre-approved-batch:` and `state:`.** Every
> other line here is human-authored, and a resume never rewrites it.

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

## Field reference (the `{...}` tuple, R1.1)

`{ feature-id, declared-surface (globs), depends_on, accept-seed }` — plus the
`pre-approved-batch` and `state` lines. Where each field flows downstream:

| Manifest field | Flows to |
|----------------|----------|
| `### <feature-id>` (heading) | the spec's `feature-id:` and the `specs/<feature-id>/spec.md` dir |
| `declared-surface:` (globs) | copied **verbatim** into the spec's `## Declared Surface` → `declared-surface:` list (R2.1) |
| `depends_on:` | the spec's `depends_on:` AND build-order's ledger `depends_on:` |
| `accept-seed:` | seeds the spec's R0 acceptance sub-requirement AND build-order's ledger `accept:` field |
| `## Shared Decisions` / `SD<n>` | inherited **verbatim** at the top of every generated spec's `## Decisions` |
| `pre-approved-batch:` | **machine-written, both directions** — `no` → `yes` post-gate, `yes` → `no` on resume for a changed or added entry; the specify-batch bypass line (T1 §3) |
| `state:` | **machine-written** — `pending` \| `generated`; decompose's own resume ledger. Nothing downstream reads it (T1 §2) |

The first four fields plus `## Shared Decisions` are the **human-owned** ones, and they are
also exactly what the D20 entry digest hashes — `state:` and `pre-approved-batch:` are
excluded, because the machine flips them on every normal run and hashing them would make
every entry read as "changed" on the next resume.

## Notes

- **Globs.** Each `declared-surface:` entry is a repo-root-relative POSIX **path glob**
  (no leading `/`, no `./`). A directory is owned by an explicit `/**` suffix (decompose
  always emits this); a bare path with no wildcard matches that one path only. Overlap is
  a deterministic non-empty glob set-intersection per the T1 §1 glob semantics — computed by
  `${CLAUDE_PLUGIN_ROOT}/skills/coherence-audit/scripts/glob-overlap.sh`, the one shared
  implementation both decompose's pre-flight and coherence-audit's overlap tier call. Hand it
  **bare globs, one per line** — it does not strip the `- ` bullet prefix.
- **Ordering.** List features topologically — every feature appears after the features
  it `depends_on`. `depends_on: []` marks a root.
- **`state:` is decompose's resume ledger.** Two values only. Every entry is written
  `pending` when the manifest is created, **before any spec exists**; an entry flips to
  `generated` **only after** that feature's `specify` call returns *and* its `spec.md` has
  been stamped with the D20 `decompose-entry` marker — stamp first, flip second. A crash
  mid-generation therefore leaves `pending`, so the feature is regenerated rather than
  trusted. A manifest written before `state:` existed is migrated once on the next resume:
  spec exists → `generated`, else `pending`.
- **`pre-approved-batch:` flips both ways.** `no` → `yes` only on an explicit human Approve.
  But on a resume, decompose resets it **`yes` → `no`** for every entry whose D20 digest
  differs from the stamp (the human edited it) and for every newly added entry, then re-fires
  the gate **scoped to just those entries**. Unchanged entries keep `yes` and are not
  re-asked. Without the reset, a changed entry would still read `yes` from the original gate
  and `specify mode: batch` would bypass its prompts for a partition no human ever approved.
  On **Abort**, a changed entry keeps `state: generated` with `pre-approved-batch: no` (its
  spec body is still there to preserve); a newly added entry stays `pending` / `no`.
- **Every rewrite of this file is atomic** (temp file in the same directory + rename), so no
  reader can observe a torn manifest and no human can approve one.
- **Disjoint by construction.** Decompose derives the partition so feature surfaces are
  *disjoint* (or only ordered-shared); its pre-flight (R1.2) fails fast on any UNORDERED
  glob collision before generating specs.
- **Shared Decisions are common ground.** Identical inherited `SD<n>` entries are NOT a
  contradiction; only divergent feature-local `D<n>` decisions on a shared surface are
  contradiction candidates (resolved later by coherence-audit, not here).
