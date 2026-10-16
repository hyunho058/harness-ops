# roster-schema.md — the crew roster data contract

> `roster.md` is the record of **who was assigned, who was excluded and why, and what
> was installed at the moment of assignment**. It is written once per run at the end of
> Phase 2 and then **frozen**. Two consumers bind to it: `pipeline.md`, whose
> `contract_ref` fingerprint is computed from a strictly limited subset of these fields
> (§4), and the human, for whom the `excluded` block is the only audit trail that a role
> was dropped on purpose (D5).
> **This doc defines DATA + field semantics only.** The capability analysis, the
> skill-scan, and the literal-output confirmation procedure live in `crew`'s SKILL.md;
> they are referenced here, never re-specified.

Four sub-contracts:
1. **Assigned roles** — `role` / `owner` / `output` / `pass_criteria` (§1 — D4, R3.1).
2. **Excluded roles** — role + reason, grounded in an observation (§2 — D5, R3.2).
3. **Observation snapshot** — what was installed when assigning (§3 — D31, R3.3).
4. **`contract_ref` input** — the strictly limited fingerprint set (§4 — D35, R3.4).

---

## 1. Assigned roles  (D4, D36, R3.1)

A role is defined by **what file it produces and what makes that file pass** — never by a
persona. "You are a designer" produces a designer-sounding voice and a review that ends in
"looks good"; the next stage needs a file and a bar (D4).

```markdown
## Roles
### designer
- owner: expert:designer
- output: specs/<feature>/design.md
- pass_criteria: every screen has default / empty / loading / error states and a
  responsive breakpoint
- assignment: confirmed
- evidence: seed references/experts/designer.md
```

| Field | Form | Meaning |
|-------|------|---------|
| `role` | kebab string, the `###` heading | The capability this row covers. Unique within the file. |
| `owner` | `skill:<name>` or `expert:<name>` | Who performs it. **Not** part of the fingerprint (§4). |
| `output` | repo-relative path | The single file this role produces. Part of the fingerprint. |
| `pass_criteria` | one or more lines | The bar the output must clear. A review gate is derived from this, so it must be checkable by reading the output, not by taste. |
| `assignment` | `confirmed` \| `provisional` | See below. A roster with any `provisional` row **cannot be frozen** (R2.5). |
| `evidence` | free text | Why this owner was confirmed: the literal output path found in the skill's SKILL.md, or the seed file used. |

### Assignment confirmation (D36, R2.2–R2.5)

`owner: skill:<name>` is **provisional until a literal output path is found in that
skill's SKILL.md body**. Description text does not count — in this ecosystem a
`description` is a trigger phrase, not a capability contract, so a skill whose description
mentions "design" can be matched confidently and wrongly.

| Outcome | `assignment` | Then |
|---------|--------------|------|
| Literal output path found (e.g. specify's `{specDir}/spec.md`) | `confirmed` | Keep the skill owner. |
| SKILL.md readable, no literal output path | — | Fall back: `owner` becomes `expert:<name>`, record `fallback: no-literal-output`. |
| SKILL.md not readable from any of the 5 scan paths | — | Fall back: record `fallback: unverifiable`. |

CLI-built-in skills (`code-review`, `security-review`) have no file on any scan path, so
they always take the third row and can never be confirmed. They are still scanned and
still handled by that row — the branch must stay reachable — but they are **not listed as
preferred assignment targets**, because presenting them as confirmable would let the
roster record the inevitable fallback as a deliberate choice (D3, R2.4).

### The reviewer is not a role (D43, R6.0)

The cross-functional reviewer is a **gate component**, not a roster entry. It is never
installed into the target project and never appears in `## Roles`, so it never enters the
fingerprint — a change to the reviewer seed must not invalidate a resume.

---

## 2. Excluded roles  (D5, R3.2)

Dynamic assembly has exactly one safety net: an exclusion must be an explicit, recorded
judgement. A feature with a UI whose designer quietly fell off the roster is invisible
otherwise.

```markdown
## Excluded
- role: designer
  reason: no-UI
  basis: brief.md › reconnaissance — no view/template/component files found
```

| Field | Form | Meaning |
|-------|------|---------|
| `role` | kebab string | The capability deliberately not staffed. |
| `reason` | short token | `no-UI`, `no-tests`, `not-applicable`, … |
| `basis` | pointer | **Where the judgement came from.** A reason with no basis is a guess; Phase 1.5 reconnaissance is what makes it a finding (R1.2, R1.3). |

`excluded` is **not** part of the fingerprint (§4): re-deciding an exclusion is a roster
change a human should see, but it does not relocate any artifact, so it must not discard
a resume.

---

## 3. Observation snapshot  (D31, R3.3)

The same request produces a different flow in a different project, because assignment
depends on what is installed. Without a snapshot, "why did a designer get attached last
time but not now?" is unanswerable.

```markdown
## Snapshot
- observed_at: <stamp>
- scan_paths: 5/5 reachable
- skills:
  - specify @ harness-ops (plugin)
  - loop @ harness-ops (plugin)
  - qa @ harness-ops (plugin)
```

Record the skill name, where it was found, and a version when the source exposes one.
This block is **descriptive, never load-bearing**: nothing branches on it at runtime, and
it is excluded from the fingerprint (§4). That exclusion is the whole point — an unrelated
skill update must not invalidate every resume.

---

## 4. `contract_ref` — the fingerprint input  (D35, R3.4, R9.3)

`pipeline.md` carries a `contract_ref`. On resume it is **recomputed from the on-disk
`roster.md`** — Phase 2 is not re-run, exactly as `loop` recomputes from the on-disk
`loop.md` rather than re-deriving its contract (`skills/loop/SKILL.md:204-207`).

**The input is two fields and nothing else:**

```
for each row in ## Roles, sorted by role name:
    "<role>\t<output>\n"
```

`sha256` of that byte string, lowercase hex.

| Field | In fingerprint? | Why |
|-------|-----------------|-----|
| `role` | **yes** | A role appearing or disappearing is a contract change. |
| `output` | **yes** | A relocated artifact invalidates every downstream path. |
| `owner` | **no** | An owner can flip from `skill:` to `expert:` purely because a skill version changed its SKILL.md body (§1). Including it would let an unrelated update overturn the owner, change the fingerprint, and discard the run state — reintroducing by the back door the exact failure §3 exists to prevent. |
| `pass_criteria` | no | Tightening a bar is a gate change, not a relocation; it is caught by the gate, not by resume. |
| `excluded` | no | See §2. |
| `snapshot` | no | See §3. |

What this fingerprint detects is therefore **a hand-edit to the roster's role set or
output paths** — and that is the intent, not a limitation. Environment drift is
deliberately invisible to it.

Verifiable form: *"editing only the `snapshot` block still resumes = yes; editing a role's
`output` path goes stale = yes"* (R9.3).

---

## 5. Freeze  (R2.5)

The roster is frozen — written and not modified again for the run — only when **every row
is `confirmed`**. A `provisional` row means Phase 3 has not established what the artifact
contract is, so a pipeline built on it would name a file nobody has agreed to produce.
