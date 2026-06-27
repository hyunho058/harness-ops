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
> specify analogue of loop's `pre-approved-unattended: yes`.

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

## Field reference (the `{...}` tuple, R1.1)

`{ feature-id, declared-surface (globs), depends_on, accept-seed }` — plus the
`pre-approved-batch` line. Where each field flows downstream:

| Manifest field | Flows to |
|----------------|----------|
| `### <feature-id>` (heading) | the spec's `feature-id:` and the `specs/<feature-id>/spec.md` dir |
| `declared-surface:` (globs) | copied **verbatim** into the spec's `## Declared Surface` → `declared-surface:` list (R2.1) |
| `depends_on:` | the spec's `depends_on:` AND build-order's ledger `depends_on:` |
| `accept-seed:` | seeds the spec's R0 acceptance sub-requirement AND build-order's ledger `accept:` field |
| `## Shared Decisions` / `SD<n>` | inherited **verbatim** at the top of every generated spec's `## Decisions` |
| `pre-approved-batch:` | `no` → `yes` post-gate; the specify-batch bypass line (T1 §3) |

## Notes

- **Globs.** Each `declared-surface:` entry is a repo-root-relative POSIX **path glob**
  (no leading `/`, no `./`). A directory is owned by an explicit `/**` suffix (decompose
  always emits this); a bare path with no wildcard matches that one path only. Overlap is
  a deterministic non-empty glob set-intersection per the T1 §1 glob semantics.
- **Ordering.** List features topologically — every feature appears after the features
  it `depends_on`. `depends_on: []` marks a root.
- **Disjoint by construction.** Decompose derives the partition so feature surfaces are
  *disjoint* (or only ordered-shared); its pre-flight (R1.2) fails fast on any UNORDERED
  glob collision before generating specs.
- **Shared Decisions are common ground.** Identical inherited `SD<n>` entries are NOT a
  contradiction; only divergent feature-local `D<n>` decisions on a shared surface are
  contradiction candidates (resolved later by coherence-audit, not here).
