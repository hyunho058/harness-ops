---
name: crew
argument-hint: "<feature request>"
description: |
  Take one feature request from definition to running code: define it, scout the target
  project, assemble a crew from installed skills plus purpose-built experts, fix each
  stage's artifact and pass criteria in a resumable ledger, get ONE human approval, then
  run the stages to completion.
  Assignment prefers already-installed skills and creates an expert only for the gaps.
  Every stage's output, criterion and status lives in specs/<feature>/pipeline.md, so a
  run survives context compaction and resumes where it stopped.
  Use when: "/crew", "crew", "build this feature end to end", "assemble a team for",
  "정의부터 실행까지", "기능 하나 처음부터 끝까지", "전문가 편성해서 만들어줘".
  Do NOT use for: one spec (use harness-ops:specify), one verification loop
  (use harness-ops:loop), many existing specs (use harness-ops:build-order), or adding a
  single expert (use harness-ops:expert).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Agent
  - AskUserQuestion
  - Skill
---

# /crew — define, assemble, run

> **Runtime contract — read this first.** Before executing any step below, read
> `../../references/runtime-tools.md`. This skill names **capabilities**, not runtime tool
> names, and cites pinned **procedure ids** (`` `capability:<id>` ``) wherever the outcome
> depends on running exactly that procedure. The map turns each one into the concrete call for
> the runtime you are in. Do not substitute your own reasoning for a cited procedure id.

crew owns **who does what, in what order, producing which file, judged by which criterion**.
It owns almost nothing else: the spec comes from `specify`, development and verification from
`loop`, testing from `qa`, expert creation from `expert`. Gates are not reimplemented here.

## Core Rules

1. **A role is an output file plus a pass criterion** — never a persona (`roster-schema.md` §1).
2. **Installed skills first, experts only for the gaps** — and an assignment is provisional
   until a literal output path is confirmed in that skill's own body.
3. **The ledger is the truth.** `pipeline.md` is flushed before each action, not after, and a
   resume reads it rather than reconstructing state.
4. **One human approval, and crew may not manufacture it.** The approval record is written
   only as the direct result of an `Approve` answer.
5. **No file enters the target project's *harness* before that approval** — no expert file,
   no `.claude/agents/` directory. crew's own planning artifacts under `specs/<feature>/`
   are written as they are produced; the approval prompt exists precisely to show them.
6. **Gates are delegated.** Reviews go through `references/review-gate.md`; development
   verification is `loop`'s three gates.
7. **Park, don't abort.** A failed stage parks; stages that do not depend on it continue.
8. **git is opt-in and never forced.** Default is zero git writes.

## Contracts this skill binds to

| File | What it fixes |
|---|---|
| `references/roster-schema.md` | roster fields, exclusions, snapshot, the `contract_ref` input |
| `references/pipeline-schema.md` | ledger fields, four statuses, flush rule, approval record |
| `references/review-schema.md` | review artifact shape and field ownership |
| `references/review-gate.md` | how a review is run and what proves it ran |
| `../../references/experts/*.md` | read-only seeds: the designer, and the reviewer prompt |

---

## Phase 0 — Resume, adopt, or stop

Run this **before anything else**.

**First resolve which directory to look at.** The slug is not confirmed until Phase 1, so
Phase 0 works from a *candidate*: use the feature name or `specs/` path if the invocation
named one, otherwise derive a provisional kebab-case slug from the request. Then read that
`<spec_dir>` with `capability:list-paths`.

If Phase 1 confirms a **different** slug, re-run this branch against the confirmed directory
**before writing anything into it** — that means before Phase 1 writes `brief.md`, not merely
before Phase 3 writes the ledger. A confirmed slug can land on a directory whose contents fall
in the **STOP** row, and writing into it first is precisely the "do not touch work you did not
create" boundary that row exists to enforce.

| What is there | Branch |
|---|---|
| `pipeline.md`, floor fields parse, `contract_ref` matches the current roster | **RESUME** |
| `pipeline.md` present but floor unparseable, or `contract_ref` mismatched | **STALE** |
| No `pipeline.md`, but `spec.md` / `loop.md` present | **ADOPT** |
| No `pipeline.md`, other unrecognised content | **STOP** |

**RESUME.** Skip `done` stages and continue from the first `pending` one. Recompute
`contract_ref` **from the on-disk `roster.md`** — do not re-run Phase 2, which would re-ask
the human every time a run resumes.

**STALE.** The run state belongs to a different contract. Do not silently rebuild it: report
what mismatched and ask via `capability:ask-user` whether to discard and start fresh.

**ADOPT.** Someone already started this feature with `specify` or `loop`. Take it over:
run Phase 2 and Phase 3 first — `roster.md` must exist before `contract_ref` can be computed —
then write a `pipeline.md` whose already-finished stages are marked `done`. A stage is `done`
only when its declared `output` exists; the development stage additionally requires that
`progress.md` is **absent**, since that file exists only while a `loop` run is in flight. When
in doubt mark it `pending`: redoing a stage is cheaper than skipping one that never finished.
An adopted `spec.md` has never been through crew's review, so **rejoin at Phase 3.6**, not at
Phase 5. No run reaches the execution segment without the Phase 4 approval.

**STOP.** Escalate. Overwriting a directory whose contents this skill cannot account for is
exactly the inherited boundary against destroying work it did not create.

---

## Phase 1 — Define the feature

Judge whether the request is actionable: is the target clear, is the scope bounded, is
"done" recognisable? **You** make that judgement here. An ambiguity score cannot gate it,
because that score is something the interview *produces* after several rounds, not something
available beforehand.

If it is not actionable, run `Skill(skill="harness-ops:requirements-interview")`. That skill
deliberately writes no file, so **crew** records the result: write `brief.md` with
`capability:write-file`.

Fix the **feature slug** here (kebab-case). It is the single source of truth for every path
from now on and is passed explicitly to sub-skills rather than re-derived by them. Record it
as `pipeline.md`'s `feature` field the moment Phase 3 writes that file.

---

## Phase 1.5 — Scout the target project

Not optional. A globally-installed skill knows nothing about the project it landed in, and
Phase 2's capability analysis is guesswork without this.

Determine, each with the evidence path that established it, using `capability:search-content`
and `capability:list-paths`:

- **Stack** — languages, frameworks, package manifests.
- **UI present?** — views, components, templates, styles.
- **Test command** — the runner and how it is invoked.

Record all three in `brief.md`. Do not ask the human for the stack: monorepos and multiple
runners make an honest answer unreliable, and the code already holds it.

**Empty project.** If there are no source files, record `reconnaissance: empty-project` and
carry "no UI" and "no test runner" forward as *findings*. Phase 2 then excludes those roles
on evidence rather than on a guess.

---

## Phase 2 — Assemble the roster

### 2.1 Scan installed skills

Collect `SKILL.md` from all five paths, extracting each skill's `name` and the first 200
characters of its `description`:

```
~/.claude/skills/**
~/.claude/plugins/**/skills/**
{PROJECT}/.claude/skills/**
{PROJECT}/.claude-plugin/**
{PROJECT}/skills/**
```

### 2.2 Confirm every assignment against a literal output path

A `description` in this ecosystem is a **trigger phrase, not a capability contract**. Matching
on it alone attaches a role to a skill that never agreed to produce that artifact — `scaffold`
mentions "architecture" and "design" and will match a designer capability confidently and
wrongly.

So an assignment to a skill stays **provisional** until its SKILL.md body states a literal
output path:

| Outcome | Result |
|---|---|
| Literal path found | `assignment: confirmed`, keep the skill owner |
| Body readable, no literal path | fall back to an expert, record `fallback: no-literal-output` |
| Body unreadable on all five paths | fall back to an expert, record `fallback: unverifiable` |

Resolve the skill's body at the path the scan found it, not at a repo-relative guess — in a
target project these skills live under the plugin cache.

CLI built-ins (`code-review`, `security-review`) have no file on any scan path, so they always
take the third row. They are scanned and handled there, but they are **not** presented as
confirmable targets.

The **reviewer is not a roster role**. It is a gate component, run from its seed and never
installed (`references/review-gate.md` §2).

### 2.3 Record exclusions with their basis

Every capability the feature does not staff gets a row in `excluded` with a `reason` and the
`basis` that produced it — normally a Phase 1.5 finding. This is the only audit trail that a
role was dropped deliberately rather than forgotten.

### 2.4 Freeze

Write `roster.md` per `references/roster-schema.md`. Freeze it **only when no row is
`provisional`**. Then compute `contract_ref` from the role names and output paths alone.

---

## Phase 3 — Write the ledger

Write `pipeline.md` per `references/pipeline-schema.md`: one stage per roster role, each with
`owner`, `output`, `pass_criteria`, `depends_on` and `status: pending`, plus the header floor
fields `feature`, `stage`, `contract_ref`.

**Flush before acting, always.** Every status transition reaches disk *before* the action it
describes, written temp-then-rename. A crash between a call and its record is the case this
ledger exists for.

---

## Phase 3.5 — Produce the spec

```
Skill(skill="harness-ops:specify",
      args="specDir: specs/<feature>
handoff: none
<the goal, plus brief.md's reconnaissance findings>")
```

Both arguments matter. `specDir` stops `specify` deriving a different directory from the goal
string. **`handoff: none` is load-bearing**: without it `specify`'s final gate is "Execute",
which stamps approval onto the spec and hands straight off to execution — bypassing the review
below, crew's own approval, the expert installs and this ledger, and asking the human to
approve twice.

---

## Phase 3.6 — Review the spec, before the approval

Run `references/review-gate.md` against `<spec_dir>/spec.md`.

`BLOCK` → present the findings and let the human drive `specify`'s Revise loop, then
re-review with `iteration` incremented. The human is the rework owner here because `specify`
is an interview skill and cannot be driven unattended — and because editing a document after
the human approved it is precisely what the approval is meant to prevent.

If anti-spin trips (an iteration resolved nothing), do not start another round. Carry the
unresolved findings into Phase 4 and show them **with** the approval prompt.

---

## Phase 4 — One approval, then the only writes

### 4.1 Ask once

A single `capability:ask-user`. Present all of it together:

- the reviewed `spec.md` and its verdict, plus any unresolved findings
- the frozen `roster.md` — assigned and excluded
- the stage order from `pipeline.md`
- **the expert files that will be written**, by path, and any directory to be created
- whether the execution segment will run unattended

This one question covers entering the execution segment, writing expert files, and creating
`.claude/agents/`. Do not ask about those separately.

### 4.2 On Approve

Write the approval block — `approved_by`, `approved_at`, `approved_contract_ref` — as the
**direct result of that answer and by no other route**. Never from an invocation marker,
never during a resume, never by inferring intent. A marker alone must never produce it: that
would be crew approving a plan the human never saw.

Then install the experts in **one batch**:

```
Skill(skill="harness-ops:expert",
      args="role: designer
output: specs/<feature>/design.md
pass_criteria: <from roster.md, verbatim>
brief: specs/<feature>/brief.md
approved_by: specs/<feature>/pipeline.md")
```

`approved_by` is what lets `expert` skip its own confirmation — this approval already absorbed
it. A standalone `/expert` call keeps that confirmation.

If the project has no `.claude/agents/`, create it here; it was in the question above.

### 4.3 On decline

Write nothing into the target project's **harness** — no expert file, no agent directory.
The planning artifacts under `specs/<feature>/` stay as they are, and the ledger is still
updated to record the decline. Post-approval stages stay `pending`. Stages already completed in front of the human — `specify`, the spec
review — stay `done`; they happened while they watched.

---

## Phase 5 — Run the stages

### 5.1 Pick the path

**Unattended requires both**: the invocation carried the unattended marker **and** the
approval block exists. Either alone means interactive — approval by itself does not make a
run unattended. If the approval block's `contract_ref` differs from the current roster
fingerprint, the human approved a different plan: stop and re-ask.

### 5.2 Drive the ledger

For each ready stage — `pending`, with every `depends_on` `done`:

1. Flush `status: in-progress`.
2. Call the owner.
3. Record the result: `done`, or `parked` with a reason.

**Call leaf skills directly**, passing the preceding artifacts explicitly:

```
Skill(skill="harness-ops:loop",
      args="specDir: specs/<feature>
Read specs/<feature>/design.md and specs/<feature>/review-design-1.json before
implementing, and include their pass criteria in the gate derivation.")
```

Name the paths and say they must be read and folded into gate derivation. Also pin any output
location that would otherwise land outside the feature directory — `qa` defaults to
`.qa-reports/`, so pass `Output to specs/<feature>` in its arguments.

Direct calls are what make this injection arrive intact. A delegate reconstructs arguments
from its own analysis and has no obligation to carry these paths.

### 5.3 The interactive path delegates exactly one stage

On the interactive path the **development stage** goes to
`Skill(skill="harness-ops:agent-orchestrate")`, unmodified, so its pattern confirmation and
its verification-gate disclosure both happen in front of the human.

Every other stage — review, design, QA — crew drives directly on both paths. Their owner and
output are already fixed in the ledger, so there is no pattern left to choose, and a delegated
stage's transitions cannot be flushed because crew does not observe them.

Record what actually verified the work. On the unattended path that is always `loop`. On the
interactive path the human may pick a non-Loop pattern or decline the verification gate; then
the two paths did **not** reach the same verifier and `pipeline.md` says so rather than leaving
the run looking equally evidenced.

### 5.4 Verification is `loop`'s, not crew's

crew implements no verification of its own. `loop`'s three gates and its evidence report are
the check, and `agent-orchestrate`'s own gate is a call to the same skill — so both paths reach
one verifier. Building a second one here would be reimplementing exactly what rule 6 forbids.

### 5.5 Boundaries and parking

The six autonomy boundaries are `loop`'s and are inherited wherever `loop` actually runs:
schema change, data-losing migration, auth or permission policy, payment or security, conflict
with the approved spec, and destroying work it did not create. On the interactive path they
apply only when `loop` runs — record it when it did not.

Park with the right reason, because the morning triage depends on the difference:

| Situation | `reason` |
|---|---|
| A boundary, a gate that could not be cleared, a finding nobody may resolve unattended | `escalated` |
| The call itself failed — missing binary, denied tool, crash | `error` |

A finding that targets `spec.md` after the approval parks its stage; it never edits the spec.

Team Mode is unreachable unattended, since `agent-orchestrate` is never called there. If a
human selects it on the interactive path, the underlying team tooling is absent in this
environment, the call fails, and that stage parks with `error`.

---

## Phase 6 — Commit, only if asked

Default: **zero git writes**. Everything below happens only when the invocation asked for a
commit.

**Check ignore rules before creating a branch.** Order matters: reversing it strands an orphan
branch on the stop path.

1. Feed the **full file list** — not the directory — through `git check-ignore --stdin` via
   `capability:run-command`. A directory-level check passes while a project's `*.json` rule
   quietly drops every review artifact.
2. Branch on three exit states, not two: `0` ignored, `1` not ignored, **`128` not a git
   repository**. A plain conditional reads `128` as "not ignored" and proceeds.
3. If anything is ignored, **stop and tell the human**. Never force it through.

Commit set: the `output` of every `done` stage that actually exists, plus the expert files
written in Phase 4, plus the development stage's working-tree changes. Include
`loop-escalation.md` if the run parked. Exclude `progress.md`, which `loop` declares transient
and deletes on a clean exit. A role that was excluded has no output, and its absence is not a
failure.

Commit once, at the end of the execution segment, not per stage. **If any stage parked, say
so in the commit message**, naming the stage and its reason — otherwise the commit reads as a
completed feature and whoever picks it up has to rediscover that it is not.

Follow the project's own git procedure: confirm the staged set, commit from a message **file**
rather than an inline string, verify the committed message against that file, and re-read
`HEAD` before pushing. Then confirm with `git show --stat` what actually landed, and report
success **only** after seeing it. Never merge. Never force-push.

---

## Checklist Before Stopping

- [ ] Phase 0 branch was chosen deliberately and recorded
- [ ] `brief.md` carries stack, UI and test command, each with its evidence path
- [ ] Every assignment is `confirmed`; the roster froze with no `provisional` row
- [ ] `roster.md` records exclusions with a basis, and a snapshot outside the fingerprint
- [ ] `contract_ref` was computed from role names and output paths only
- [ ] `specify` was called with both `specDir` and `handoff: none`
- [ ] The spec was reviewed **before** the approval prompt
- [ ] Exactly one approval question was asked
- [ ] The approval record exists only because the human answered Approve
- [ ] No expert file and no `.claude/agents/` directory existed before that answer
- [ ] Every stage transition was flushed before its action
- [ ] Preceding artifact paths were injected into every leaf call
- [ ] Parked stages carry `escalated` or `error`, chosen correctly
- [ ] Verification is recorded as what actually ran
- [ ] git untouched unless asked; if asked, ignore-checked first and `git show --stat` confirmed
