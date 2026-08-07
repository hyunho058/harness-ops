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

> **Exactly three verdict tokens — and `unverified` resolves to `BLOCK`.** A tier that could not run
> at all (tier 2's `glob-overlap.sh` unavailable, or no `Agent` tool for tier 3) is labelled
> `unverified` in the Summary below, and an `unverified` tier forces **`verdict: BLOCK`** — never
> `WARN`, never `OK` (D8, R7.4). The caller contract admits only `BLOCK | WARN | OK`, so a label
> that resolved to nothing would leave callers unable to branch; it resolves to BLOCK because an
> *uncomputable* collision check is strictly **less** informed than a known collision, and a WARN
> would let a set be built on a check that never ran.

## Summary

| tier | classification | findings | severity |
|------|----------------|----------|----------|
| contradiction | incompatible (same role, conflicting choice) | <n> | **BLOCK** |
| overlap | unordered (no `depends_on` path between them) | <n> | **BLOCK** |
| redundancy | near-duplicate Requirements/goal | <n> | warn |
| undeclared | no `## Declared Surface` / empty `declared-surface:` | <n> | warn |
| unverified | a tier that could not RUN (script or `Agent` unavailable) | <n> | **BLOCK** |

- pairs sharing a surface (non-empty glob intersection): <n>   # `unverified — not computable` if tier 2 could not run
- tiers that could not run: <none | overlap: `glob-overlap.sh` unavailable | contradiction: no `Agent` tool>
- **block-tier findings: <n>**  → verdict is `BLOCK` iff this is > 0 (R4.1) **or any tier above is
  `unverified`** (R7.4)

## Findings   (R3.3 — one block per conflicting pair / flagged spec)

### F<n> — <tier>: <feature-A> ⨯ <feature-B>     [ BLOCK | warn ]
- tier: contradiction | overlap | redundancy | undeclared | unverified
- pair: <feature-id A> ⨯ <feature-id B>            # a single feature-id for `undeclared`; `—` for `unverified`
- ordered?: no  |  yes (path: A → … → B)            # dependency-gating context (overlap & contradiction)
- evidence:                                          # the CITED proof, per tier:
  - overlap → the intersecting glob pair(s) **exactly as `glob-overlap.sh` printed them** on exit 1
    (normalized globs, A-major, TAB-separated): `(<globA>, <globB>)`
  - contradiction → cited `## Decisions`: A `D<i>: <title>` (chose <x>; rejected <y>) vs
    B `D<j>: <title>` (chose <z>) — same role on `<shared path>`
  - redundancy → the near-duplicate Requirement/goal text from each spec
  - undeclared → `surface undeclared; overlap unverifiable — declare to enable the check`
  - unverified → which tier could not run and why (e.g. `overlap tier unverified —
    ${CLAUDE_PLUGIN_ROOT}/skills/coherence-audit/scripts/glob-overlap.sh not found`), plus the pairs
    left unresolved as a result
- classification: incompatible | complementary | unordered-overlap | near-duplicate | surface-undeclared | tier-unverified
- verdict: block | warn                              # `unverified` is always `block` (D8, R7.4)
- to resolve (human-owned; the checker NEVER applies this): <e.g. "add a depends_on edge A→B to
  order the shared write", "reconcile A.D2 vs B.D3 — both pick the primary datastore, different
  engines", "merge the duplicate requirement", "add a `## Declared Surface` section to <feature>",
  "restore `glob-overlap.sh` / `${CLAUDE_PLUGIN_ROOT}` and re-run the audit">

## Considered, not flagged   (informative — audit completeness; these do NOT affect the verdict)

- **ordered overlaps** (a `depends_on` path makes the shared write sequential — D2/R2.3, NOT flagged):
  - <feature-A> ⨯ <feature-B>  (path: A → B)  shares `(<globA>, <globB>)`
- **complementary shares** (different roles on one path — D7/R3.2, NOT a conflict):
  - <feature-A> (storage) ⨯ <feature-B> (cache) under `<shared path>`

## Verdict

**<BLOCK | WARN | OK>** — <the rule that produced it:
"≥1 block-tier finding present, R4.1" | "the <overlap|contradiction> tier is `unverified` — it
could not run, D8/R7.4" | "only warn-tier findings, R4.2" | "no findings and every tier ran, OK">.

> If **BLOCK** and the caller is an unattended / autopilot path: this **HARD-STOPS** the run.
> A WARN there would be an unread annotation (approval was pre-batched), so a known write-collision
> or contradiction must not proceed unseen (R4.3). A human resolves it; the checker never auto-resolves.
>
> An **`unverified`** tier lands here for the same reason one step earlier: the check never ran, so
> the set is not certified — BLOCK, not WARN. Emitting this report is *not* halting anything; the
> checker remains flag-only and the caller owns what happens next.
