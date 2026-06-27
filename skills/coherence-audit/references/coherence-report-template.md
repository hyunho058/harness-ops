# coherence-report.md — <spec set name>

> Emitted by `coherence-audit` (T2). This is a **flag-only** artifact: the checker
> WRITES this report and nothing else — it never edits or rewrites a `spec.md`
> ("never push through the fence", R7.3). The human (or the calling skill —
> build-order / decompose) resolves every finding; the checker only surfaces them.
> The per-pair block below is the R3.3 verdict schema: `{verdict, cited evidence, block|warn}`.

- generated_at: <stamp>
- verdict: BLOCK | WARN | OK          # overall — the machine-readable token a caller binds to
- specs_audited: <n>   (declared: <d> | undeclared: <u>)
- input_ref: <fingerprint of the audited set — sorted feature-ids + spec paths>

## Summary

| tier | classification | findings | severity |
|------|----------------|----------|----------|
| contradiction | incompatible (same role, conflicting choice) | <n> | **BLOCK** |
| overlap | unordered (no `depends_on` path between them) | <n> | **BLOCK** |
| redundancy | near-duplicate Requirements/goal | <n> | warn |
| undeclared | no `## Declared Surface` / empty `declared-surface:` | <n> | warn |

- pairs sharing a surface (non-empty glob intersection): <n>
- **block-tier findings: <n>**  → verdict is `BLOCK` iff this is > 0 (R4.1)

## Findings   (R3.3 — one block per conflicting pair / flagged spec)

### F<n> — <tier>: <feature-A> ⨯ <feature-B>     [ BLOCK | warn ]
- tier: contradiction | overlap | redundancy | undeclared
- pair: <feature-id A> ⨯ <feature-id B>            # a single feature-id for `undeclared`
- ordered?: no  |  yes (path: A → … → B)            # dependency-gating context (overlap & contradiction)
- evidence:                                          # the CITED proof, per tier:
  - overlap → the intersecting glob pair(s): `(<globA>, <globB>)`
  - contradiction → cited `## Decisions`: A `D<i>: <title>` (chose <x>; rejected <y>) vs
    B `D<j>: <title>` (chose <z>) — same role on `<shared path>`
  - redundancy → the near-duplicate Requirement/goal text from each spec
  - undeclared → `surface undeclared; overlap unverifiable — declare to enable the check`
- classification: incompatible | complementary | unordered-overlap | near-duplicate | surface-undeclared
- verdict: block | warn
- to resolve (human-owned; the checker NEVER applies this): <e.g. "add a depends_on edge A→B to
  order the shared write", "reconcile A.D2 vs B.D3 — both pick the primary datastore, different
  engines", "merge the duplicate requirement", "add a `## Declared Surface` section to <feature>">

## Considered, not flagged   (informative — audit completeness; these do NOT affect the verdict)

- **ordered overlaps** (a `depends_on` path makes the shared write sequential — D2/R2.3, NOT flagged):
  - <feature-A> ⨯ <feature-B>  (path: A → B)  shares `(<globA>, <globB>)`
- **complementary shares** (different roles on one path — D7/R3.2, NOT a conflict):
  - <feature-A> (storage) ⨯ <feature-B> (cache) under `<shared path>`

## Verdict

**<BLOCK | WARN | OK>** — <the rule that produced it:
"≥1 block-tier finding present, R4.1" | "only warn-tier findings, R4.2" | "no findings, OK">.

> If **BLOCK** and the caller is an unattended / autopilot path: this **HARD-STOPS** the run.
> A WARN there would be an unread annotation (approval was pre-batched), so a known write-collision
> or contradiction must not proceed unseen (R4.3). A human resolves it; the checker never auto-resolves.
