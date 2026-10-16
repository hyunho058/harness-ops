# pipeline-schema.md — the crew run-state ledger contract

> `pipeline.md` is the durable ledger for one feature's run: what the stages are, who owns
> each, what it produces, what makes it pass, and where the run currently stands. It is
> the **only** thing that survives context compaction, so a resume reads it rather than
> reconstructing state. It follows `build_order.md`'s ledger pattern
> (`skills/build-order/SKILL.md:67-89, 235-271`) — the same four statuses, the same
> atomic flush on every transition, the same rule that parking one stage does not stop
> the stages that do not depend on it.
> **This doc defines DATA + field semantics only.** Stage selection, gate execution and
> the interactive/unattended path split live in `crew`'s SKILL.md.

Five sub-contracts:
1. **Header + floor fields** — what a resume requires (§1 — D23, R4.3).
2. **The human approval record** — who may write it, and when (§2 — D28, R10.2–R10.5).
3. **Stage entries** — the ledger rows (§3 — D12, R4.1).
4. **Atomic flush** — when a write must reach disk (§4 — R4.2).
5. **Attached evidence** — `load_check`, `isolation`, `verification` (§5 — D41, D16, R5.11, R6.4).

---

## 1. Header + the required-field floor  (D23, R4.3, R9.1)

```markdown
# pipeline.md — <feature>

- feature: alarm-center
- stage: design
- contract_ref: sha256:<64 hex>
- generated_at: <stamp>
- spec_dir: specs/alarm-center
- unattended_marker: false
```

**Required-field floor — `feature`, `stage`, `contract_ref`.** All three MUST be present
and parseable for a resume to proceed; every other field is read leniently. If any floor
field is missing or unparseable the file is **stale**: discard the run state and ask the
human (D20, R4.3). This mirrors `loop`'s floor rule (`skills/loop/SKILL.md:181-195`),
with one deliberate difference — `loop`'s floor includes `anti_spin` because that counter
cannot be re-derived after a compact; crew's per-stage anti-spin lives inside the review
gate's own iteration records (§5) and in `loop`'s `progress.md` for the dev stage.

| Field | Floor? | Meaning |
|-------|--------|---------|
| `feature` | **yes** | The slug crew fixed in Phase 1. It is the single source of truth for every artifact path and is passed explicitly to sub-skills (`specDir`) rather than re-derived (D19, D24). |
| `stage` | **yes** | The stage the run is positioned at. |
| `contract_ref` | **yes** | Fingerprint of the roster this run-state belongs to — computed per `roster-schema.md` §4. Recomputed on resume from the on-disk `roster.md`; a mismatch means this state belongs to a different contract and is discarded (R9.2). |
| `spec_dir` | no | Where every artifact lands (D17). |
| `unattended_marker` | no | Whether the invocation carried the unattended marker. **Alone it does nothing** — see §2. |

---

## 2. The human approval record  (D28, R10.2–R10.5)

```markdown
## Approval
- approved_by: user
- approved_at: 2026-09-21T14:02:11+09:00
- approved_contract_ref: sha256:<64 hex>
- covers: unattended-entry, expert-file-writes, agents-dir-creation
```

**Who writes it.** crew writes it — and **only as the direct result of an `Approve`
answer to the single approval prompt (R0.1)**. There is no other path to this block:

- not from an invocation marker (a marker is an intent, not an approval),
- not during a resume (a resume never manufactures an approval it did not observe),
- not by inferring what the human would have said.

Earlier drafts said "crew cannot write this", which left **no actor able to write it at
all** — a human answering an `AskUserQuestion` does not write a file, and crew has no
second skill to write it the way `decompose` writes `pre-approved-batch` for `specify`.
What must be forbidden is a write **without** the human's answer, not the write itself.

**Entry condition is an AND** (R10.4): the unattended segment begins only when
`unattended_marker` is true **and** this block exists. Either alone does nothing.

**`approved_contract_ref` is checked, not decorative** (R10.5). If it differs from the
current roster fingerprint, the human approved a different plan; stop and re-ask. This is
what stops an approval from silently transferring to a roster it never covered.

---

## 3. Stage entries  (D12, D22, R4.1, R9.6, R9.7)

```markdown
## Stages
### design
- owner: expert:designer
- output: specs/alarm-center/design.md
- pass_criteria: every screen has default / empty / loading / error states
- depends_on: []
- status: done
- reason: —

### develop
- owner: skill:harness-ops:loop
- output: specs/alarm-center/loop.md
- pass_criteria: loop's three gates all green with an evidence report
- depends_on: [design]
- status: in-progress
- reason: —
```

| Field | Form | Meaning |
|-------|------|---------|
| `owner` | `skill:<name>` \| `expert:<name>` | Copied from `roster.md`. |
| `output` | repo-relative path | Copied from `roster.md`. Also the `done` test — see below. |
| `pass_criteria` | text | Copied from `roster.md`; the review gate is derived from it. |
| `depends_on` | `[<stage>, ...]` | Stage-level edges. A parked stage blocks only its dependents. |
| `status` | `pending` \| `in-progress` \| `done` \| `parked` | The four states, matched to `build_order.md`. |
| `reason` | `escalated` \| `error` \| `—` | **Only when parked**, and the distinction is load-bearing. |

### `escalated` vs `error` — keep them apart (D22, R9.7)

`escalated` means the work reached a real boundary: an autonomy boundary, a gate that
could not be cleared, a finding nobody may resolve unattended. `error` means the skill
call itself failed: a missing binary, a denied tool, a crash. Collapsing them makes the
morning triage impossible — a tool failure is retried, a boundary is decided.

### `done` is tested by the artifact, not by a claim (R9.4)

A stage is `done` only when its declared `output` **exists**. The develop stage
additionally requires that `progress.md` is **absent**, because that file exists only
while a `loop` run is in flight (`skills/loop/SKILL.md:161`) — its presence means an
interrupted run, not a finished one. When in doubt, leave the stage `pending`: redoing a
stage costs less than skipping one that never finished.

### Parking does not stop the run (D22)

When a stage parks, continue with every stage that does not depend on it. Only the
dependent subtree waits.

---

## 4. Atomic flush  (R4.2)

**Write the transition to disk BEFORE the action it describes.** Setting a stage to
`in-progress` must reach disk *before* the leaf skill is called, not after it returns.
A crash between the call and the write is exactly the case the ledger exists for: on
resume, a stage left at `in-progress` is known to have been started, whereas one still
at `pending` is known not to have been.

Write via temp + rename, as `build_order.md` does, so a reader never observes a partial
file. Every status change, every `reason`, and the approval block (§2) are flushed this
way.

---

## 4.1 Every stage output lands in one directory  (D17, D30, R4.4)

One feature's whole history lives in `specs/<feature>/`, beside `specify`'s `spec.md` and
`loop`'s `loop.md`. A stage whose `output` resolves outside that directory is a schema
violation, not a preference:

```
specs/<feature>/
  brief.md  roster.md  pipeline.md  spec.md  design.md
  review-<target>-<n>.json  qa-report-*.md  loop.md  progress.md
```

**`qa` is the one stage that will not do this by default.** It writes to `.qa-reports/`
(`skills/qa/SKILL.md:66, 279`). That skill takes its parameters as natural-language args
and the same line shows the override form (`Output to /tmp/qa`), so crew passes
`Output to specs/<feature>` in the args. No new flag syntax is invented and `qa` is not
modified. Without that injection the QA report is the one artifact that lands elsewhere,
and the rule above holds only for the stages that happened to agree with it.

The same args carry the **preceding artifacts** a stage must read — the paths, plus that
they must be read and folded into gate derivation (D30). crew calls leaf skills directly
on the unattended path precisely so this injection arrives intact rather than being
reconstructed by a delegate (D37).

`progress.md` is the one file in this directory that is **not** committed: `loop` declares
it transient and deletes it on a clean exit (`skills/loop/SKILL.md:161`), which is also why
the repository gitignores `specs/**/progress.md` while tracking everything else here.

---

## 5. Attached evidence  (D16, D41, R5.11, R6.4)

These fields record **how much to trust a result**, and each one exists because the weaker
form of the same result is indistinguishable from the stronger one without it.

```markdown
## Evidence
- experts:
  - designer: load_check=file-only  (runtime agent list not queryable)
- reviews:
  - review-spec-1.json: isolation=headless, exit=0
  - review-design-1.json: isolation=subagent-degraded, reason=headless-spawn-failed
- verification: loop (three gates, evidence report)
```

| Field | Values | Meaning |
|-------|--------|---------|
| `load_check` | `verified` \| `file-only` | Per installed expert. `verified` = the runtime confirmed the agent is loadable. `file-only` = frontmatter parsed but the runtime could not be queried. **`file-only` is not a failure** (D41): under Claude Code there is no agent-list query API and the list is fixed at session start, so `file-only` is the normal grade at write time and is upgraded on the expert's first successful spawn. A frontmatter parse failure is a hard failure and is not recorded here — the write is reverted. |
| `isolation` | `headless` \| `subagent-degraded` | Per review. `headless` is a mechanical boundary (a separate process reads only what it was given); `subagent-degraded` is a disciplinary one (the orchestrator wrote the prompt). Recording the downgrade honestly is the point — a silent downgrade misrepresents the review's independence (D18). |
| `verification` | `loop` \| `declined` \| `<pattern>` | How the dev stage was verified. On the unattended path this is always `loop`. On the interactive path `agent-orchestrate` may pick a non-Loop pattern, and the human may decline the verification gate at its Phase 2 (`skills/agent-orchestrate/SKILL.md:231`) — then the two paths did **not** reach the same verifier, and this field says so rather than leaving the run looking equally evidenced (D16, D38). |

Review evidence itself (exit codes, output file paths, the degradation reason) lives in
the review artifact; see `review-schema.md` §3. This block is the ledger's index into it.
