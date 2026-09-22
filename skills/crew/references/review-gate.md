# review-gate.md — the crew review gate procedure

> **Runtime contract — read this first.** Before executing any step below, read
> `../../references/runtime-tools.md`. This procedure names **capabilities**, not runtime tool
> names, and cites pinned **procedure ids** (`` `capability:<id>` ``) wherever the outcome
> depends on running exactly that procedure. The map turns each one into the concrete call for
> the runtime you are in. Do not substitute your own reasoning for a cited procedure id.

One gate component, used at two places in the run. It takes an artifact and a pass
criterion, runs an **isolated** reviewer against them, and returns a verdict plus findings.
It never edits the artifact.

The data contract is `review-schema.md`; the reviewer's prompt is
`../../references/experts/cross-functional-reviewer.md`. This file is the **procedure**:
how the reviewer is launched, what counts as proof it really ran, and what happens to the
verdict.

---

## 1. Where this gate runs  (D40, D6)

| Placement | When | Rework owner |
|-----------|------|--------------|
| **Spec review** | After `specify` L0–L4, **before** the single human approval | The **human**, via `specify`'s Revise loop |
| **Design review** | After the design stage, inside the execution segment | The **designer expert**, unattended |

The spec review sits before the approval on purpose. `specify` is an interview skill and
cannot be driven unattended, so a `BLOCK` found after approval would have no one able to
act on it — and editing a document the human already approved is precisely what the
approval is supposed to prevent. Putting the gate first means the human approves a spec
that has already passed review.

**Consequence:** there is no `spec.md` rework path after the approval. A finding raised
later that targets `spec.md` parks its stage instead — see §7.

---

## 2. Assemble the reviewer prompt  (R6.0, D43)

`capability:read-file` → `../../references/experts/cross-functional-reviewer.md`.

1. Take **only** the section headed `PROMPT BODY` and everything after it, up to the
   trailing `SEED CONTRACT` comment. The material above it describes the seed to *you*, not
   to the reviewer.
2. Substitute every placeholder the seed's `SEED CONTRACT` declares: `{{target}}`,
   `{{pass_criteria}}`, `{{iteration}}`, `{{prior_review}}`. A leftover `{{...}}` is a
   defect — do not launch.
3. `{{pass_criteria}}` is copied **verbatim** from the role's `pass_criteria` in
   `roster.md`. Do not summarise or rephrase it: the gate must check the bar the roster
   promised, not your reading of it.
4. `{{prior_review}}` is the previous iteration's artifact path, or empty on iteration 1.

**Never install this seed.** It is a gate component, not a roster expert: it stays out of
the project's agent directory, out of `roster.md`, and out of the `contract_ref`
fingerprint, so changing it never invalidates a resume.

**Never include your own reasoning about the artifact.** The reviewer is given the artifact
and the contract, and nothing about why the author made the choices they made. That absence
is the separation the gate exists to create; supplying it quietly converts the check into
the author grading their own work.

---

## 3. Path A — isolated process (preferred)  (R6.1, D7, D25)

Launch the reviewer as a **separate process** via `capability:run-command`. Separation here
is mechanical rather than disciplinary: the process reads only what it was handed.

**Restrict its tools as part of this invocation.** Grant read-only access and no write tool,
using whatever the runtime's process launcher provides for that. This is a property of the
command you construct via `capability:run-command`, not a separate procedure — the map has
no entry for a restricted launch, and none is needed. On this path flag-only is mechanical:
a process with no write tool cannot edit what it reviews, and it returns its JSON as output
rather than by writing a file.

**Capture shape — this part is exact:**

- Redirect stdout and stderr to **files**.
- Use **no pipe**.
- Read the exit code from `$?` on the line immediately after.

Do **not** reach for `${PIPESTATUS[0]}` to keep a pipe: that array is bash-only, zsh spells
it `$pipestatus`, and on a zsh login shell it yields an empty value indistinguishable from
"no evidence". Do not copy the `2>&1 | head -N || true` idiom that appears elsewhere in
this repository (`../../scripts/pilot-verify.sh:192, 199, 207`) — it discards the exit code,
so a review run that way leaves no evidence at all. Removing the pipe fixes both.

**When Path A does not start.** Classify the failure using the runtime map's `## Halting`
vocabulary and **record the named message verbatim** in the evidence `reason` and in
`pipeline.md`:

| What happened | Recorded message |
|---|---|
| The launcher does not exist in this runtime | `unavailable: <procedure> not provided by <runtime>` |
| It exists but was refused — under agy headless, `run_command` is auto-denied | `denied: <procedure> requires permission not granted` |

Then go to §4. **This does not halt the run**, and that is a deliberate departure from the
map's default: the map says to halt when a *required* procedure is unavailable, but Path A
is not required — Path B is its sanctioned fallback (D18), and halting here would make every
`agy -p` environment unable to review at all. What the map's rule still buys us is the
**classification**: a denial and an absence have different fixes, so collapsing them into
"headless failed" would make the run's own logs useless for repairing it.

---

## 4. Path B — degraded to a subagent  (R6.3, D18)

When Path A cannot start, **degrade rather than stop**. A globally-distributed skill meets
missing binaries, denied permissions and auto-denied tools often enough that halting would
make whole environments unusable.

Use `capability:spawn-inline-checker`. That is the correct id: the reviewer has no file
under the harness `agents/` directory, so the named-checker procedure — whose first step
sources a body from there — is unsatisfiable, and citing it would leave the runtime to
improvise.

Isolation drops from **mechanical** to **disciplinary**, and this is the real cost: you now
write the prompt the checker sees, **and the checker is no longer tool-restricted.** The
inline-checker procedure spawns a general-purpose agent, which holds write tools; on this
path nothing but the seed's own `## Boundaries` section stops it editing the artifact it is
reviewing. Record the downgrade honestly (§5) — a silent downgrade misrepresents how
independent the review was.

**One mechanical guard survives.** Before spawning, take a digest of the target file via
`capability:run-command`; after the spawn returns, take it again. If it changed, the checker
edited what it reviewed: discard the review and park the stage with reason `error`, naming
the file and both digests.

**Do not auto-restore the file.** Reverting it would be another unreviewed write over
content this run did not author, which is the boundary the whole gate inherits. Report the
modification and leave the file for the human — they can recover it from version control,
and they need to know the checker misbehaved either way. Flag-only is a promise in the
prompt on this path, so verify it after the fact rather than trusting it.

**The degraded path carries the same evidence bar** — see §5. Without it, this path would
be a hole straight through §5: "the isolated process genuinely failed" and "the
orchestrator skipped delegation and wrote the verdict itself" would produce identical
artifacts.

---

## 5. Evidence — required on both paths  (R6.2, R6.3, D25)

**A review with no evidence is invalid.** Not weak — invalid. Discard it and treat the gate
as not run. Artifact existence proves nothing on its own: an orchestrator that skipped
delegation and wrote a well-formed verdict from its own context produces a file
indistinguishable from the delegated one.

| Path | Evidence required |
|------|-------------------|
| A — isolated process | the exit code, and the stdout/stderr file paths |
| B — degraded | **the spawn's own return** |

**The bar on Path B is the spawn's return, and only that.** Under Claude Code the spawn is
native and its return *is* the evidence. Do **not** make the subagent registry the pass/fail
bar: it exists only under agy, and there it is commonly empty, so requiring it would fail
every review on the one runtime whose `run_command` denial forces Path A into Path B — the
"whole environments unusable" outcome §4 exists to prevent. Where a registry *is* readable,
check it and record the result as corroboration (`registry: confirmed` / `unavailable` /
`absent`); an `absent` result is a finding worth surfacing to the human, not an automatic
park.

**If Path B has no spawn return, this is not a degradation — it is a non-delegation.** Park
the stage with reason `error` and say so. Treating an unevidenced Path B as "degraded"
would let every review bypass this section by claiming Path A had failed.

### Every invalid review has an outcome  (R6.5)

"Invalid, treat the gate as not run" must not mean "continue". A gate that produced no
verdict produced no `BLOCK`, and §7 only stops the next stage on a `BLOCK` — so without this
rule the run walks straight through a gate that never ran.

| Case | Outcome |
|------|---------|
| No evidence at all, Path B | Non-delegation → park, reason `error` (above) |
| Evidence present but output does not parse, or is missing reviewer-owned fields | Retry **once** — a malformed response is often transient. Still invalid → park, reason `error`. |
| Target file changed during Path B | Discard, restore, park, reason `error` (§4) |

In every row the stage does **not** advance. Record the reason in `pipeline.md` via
`capability:write-file` so the morning triage can tell a tooling failure from a real
boundary.

Record the outcome in two places:

- in the review artifact, as the caller-owned `isolation` and `evidence` fields
- in `pipeline.md` § *Attached evidence*, so the ledger alone shows how well-evidenced the
  run is (R6.4)

When a required procedure is genuinely unavailable, halt with the runtime map's named
message — `unavailable:`, `denied:` or `unresolved:`. Collapsing those into one message
makes every failure ambiguous, and the fix for each differs.

---

## 6. Build the artifact  (R6.10, `review-schema.md` §2)

The reviewer returns JSON as its **output**; **you** write the file. Where that output
lives depends on the path:

| Path | Where the reviewer's output is |
|------|--------------------------------|
| A | the captured stdout file — read it with `capability:read-file` |
| B | the spawn's return value |

1. Parse that output. It must be one JSON object and nothing else.
2. Validate the **reviewer-owned** fields only: `verdict`, `target`, `reviewer`,
   `iteration`, `findings`. Do not require `isolation` or `evidence` here — those describe
   how the reviewer was run, which it cannot observe about itself, so demanding them would
   reject a correctly-behaving reviewer.
3. Add the caller-owned fields from §5.
4. `capability:write-file` → `<spec_dir>/review-<target>-<iteration>.json`.

If stdout does not parse, the review is invalid (§5). Do not repair it by inferring what
the reviewer meant — a verdict you reconstructed is a verdict you wrote.

---

## 7. Act on the verdict  (R6.5, R6.7, R6.9)

`BLOCK` present → **the next stage does not start.** `WARN` is recorded and does not block.
`OK` passes.

Route the rework by the finding's `target`, not by which artifact was under review:

| Finding targets | Placement | Action |
|-----------------|-----------|--------|
| the reviewed artifact | either | Trigger rework by its owner. |
| `spec.md`, before the approval | spec review | Present to the human; they drive `specify`'s Revise. |
| `spec.md`, after the approval | design review | **Do not edit the spec.** Park *that stage* with reason `escalated`. |

The last row is the one that is easy to get wrong. After approval there is no actor
permitted to rewrite an approved spec, so the stage parks and a human decides. This is
distinct from `loop` reaching its "conflicts with the approved spec" autonomy boundary
during development — that is the loop's own boundary and is handled as an escalation there,
not by this gate.

**Passing findings to rework** (R6.7): the rework call names the review artifact **by path**
in its arguments and states that the findings must be resolved. Pass the path, not a
summary. A paraphrase is your reasoning re-entering a checker's output, which is the
separation §2 exists to maintain.

---

## 8. Anti-spin  (R6.8)

Re-review increments `iteration`.

**If an iteration flips no finding from fail to pass, stop.** Do not start another one.
Document review is unusually prone to a stable disagreement that reads like progress —
"still ambiguous" can be returned forever. This is `loop`'s rule and it is inherited, not
reinvented.

Where the escalation goes depends on placement:

- **Design review (execution segment)** — park the stage with reason `escalated` and
  continue with the stages that do not depend on it. Parking one stage does not stop the
  run.
- **Spec review (before the approval)** — the human is already present. Via
  `capability:ask-user`, show the unresolved findings **alongside** the approval prompt and
  let them approve anyway or stop. Do not pass it silently, and do not halt without asking:
  both take a decision that is theirs to make.
