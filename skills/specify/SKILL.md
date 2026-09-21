---
name: specify
argument-hint: ""
description: |
  Turn a goal into an implementation plan (spec.md).
  Simplified layer chain: L0:Goal → L1:Context → L2:Decisions → L3:Requirements → L4:Tasks.
  Evidence-based clarity scoring at L2. User approves at L2, L3, L4.
  Output is a single spec.md file written with the Write tool.
  Use when: "/specify", "specify", "plan this"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Agent
  - Bash
  - Write
  - AskUserQuestion
  - Skill
---

# /specify — Spec Generator

Generate a spec.md through a structured derivation chain.
Each layer builds on the previous — no skipping, no out-of-order writes.

---

## Core Rules

1. **Write tool is the writer** — All spec output goes to `{specDir}/spec.md` via the Write tool. No CLI, no JSON.
2. **Append, don't overwrite** — Read existing spec.md before writing. Append new sections or update specific sections in place using Edit.
3. **Reference before writing** — Read the reference file for the current layer (`references/L*`) before constructing content.
4. **Validate at layer transitions** — After writing each layer, read spec.md and verify required sections exist.
5. **One layer at a time** — Complete and validate each layer before advancing.

---

## Spec Directory

`{specDir}` is the directory every layer writes into — the placeholder used throughout
this skill and its references. It resolves by the **first rule that applies**:

| # | Condition | `{specDir}` |
|---|-----------|-------------|
| 1 | `specDir: <path>` passed in the invocation (opt-in, additive) | `<path>` verbatim |
| 2 | `mode: batch` + `feature-id: <id>` (see `## Batch Mode`) | `specs/<id>/` |
| 3 | Otherwise — a bare invocation | `specs/{name}/`, `{name}` = kebab-case derived from the goal |

Rule 3 is the pre-existing behaviour and is **unchanged**: a bare `/specify "goal"` with
no marker derives the name from the goal exactly as before. Rules 1 and 2 are opt-in;
neither fires unless the caller passes its marker.

```
{specDir}/spec.md
```

Create the directory at Session Init:
```bash
mkdir -p {specDir}
```

**Why rule 1 exists.** A caller that already owns the feature slug — because it wrote it
into its own ledger before calling specify — must not have specify re-derive a different
one from the goal string. Passing `specDir` makes the caller's ledger the single source
of truth for the path, so the caller's other artifacts land in the same directory as
`spec.md`. Do not sanitise, re-case, or append to the path given; use it as passed.

---

## Layer Flow

Execute layers sequentially. Read each reference file just-in-time.

| Layer | Read Reference | What | Gate |
|-------|----------------|------|------|
| L0 | `references/L0-L1-context.md` | Mirror → Goal, Non-goals, Confirmed Goal | User confirms mirror |
| L1 | (same file) | Codebase research → Research section | Auto-advance |
| L2 | `references/L2-decisions.md` | Interview → Decisions + Constraints | Self-validate + L2-reviewer + User approval |
| L3 | `references/L3-requirements.md` | Derive requirements + sub from decisions | Self-validate + User approval |
| L4 | `references/L4-tasks.md` | Derive tasks + external deps, Plan Summary | Self-validate + User approval |

### Session Init (before L0)

```bash
mkdir -p {specDir}
```

Then create spec.md with initial content via Write tool.

---

## User Approval Protocol

Three approval gates (L2, L3, L4). Each uses the same pattern:

```
AskUserQuestion(
  question: "Review the {items} above. Ready to proceed?",
  options: [
    { label: "Approve", description: "Looks good — proceed to next layer" },
    { label: "Revise", description: "I want to change something" },
    { label: "Abort", description: "Stop specification" }
  ]
)
```

- **Approve** → advance to next layer
- **Revise** → user provides corrections, update spec.md sections, re-present (loop until approved)
- **Abort** → stop

At the **final gate (L4)** the "Approve" option is "Execute". On Execute, specify
records approval and then hands the approved plan off to execution via
`Skill(skill="harness-ops:agent-orchestrate")` — see `references/L4-tasks.md`.
specify never writes task code itself; it produces the plan and delegates the
*how* to agent-orchestrate, which still confirms the execution pattern with the user.

> **Handoff opt-out (opt-in, additive — see `## Handoff Mode` below):** when specify is
> invoked with the marker `handoff: none`, the L4 final option is presented as
> **"Approve"** instead of "Execute" and, on approval, specify records approval and
> **returns to its caller without invoking `agent-orchestrate`**. Every gate still runs —
> this removes the *handoff*, not any *gate*. A bare invocation with no marker hands off
> on Execute exactly as before.

> **Batch-mode bypass (opt-in, additive — see `## Batch Mode` below):** when specify
> is invoked with the marker `mode: batch` AND the feature's partition-manifest entry
> carries `pre-approved-batch: yes`, SKIP each of these three (L2 / L3 / L4)
> `AskUserQuestion` gates — and the L0 mirror confirmation — and proceed with the
> derived result (the human already owns the bar via decompose's ONE partition gate).
> A bare invocation with no marker runs every gate exactly as before.

---

## Batch Mode — additive, opt-in bypass (mirrors loop's `pre-approved-unattended`)

specify gains ONE additive, opt-in batch path — the structural twin of loop's
`pre-approved-unattended` bypass (`skills/loop/SKILL.md:231-239, 438`). This batch
path is the ONLY change to specify; the interactive L0–L4 core stays byte-unchanged,
and a bare `/specify "goal"` with no marker behaves EXACTLY as before.

**Bypass condition (marker AND line — BOTH required).** The bypass fires *iff*
specify is invoked with the marker `mode: batch` **AND** the feature's
partition-manifest entry carries the line `pre-approved-batch: yes` — written by
`decompose` into the manifest (see
`skills/coherence-audit/references/declared-surface-schema.md` §3) only after the
human approves decompose's ONE partition gate. Either alone does nothing. This is the
exact analogue of loop's `mode: unattended` + `pre-approved-unattended: yes` rule.

**What the bypass SKIPS — the human `AskUserQuestion` approval prompts ONLY:**
- the **L0 mirror** confirmation ("Does this match your intent?")
- the **L2 decisions** approval (Approve / Revise / Abort)
- the **L3 requirements** approval (Approve / Revise / Abort)
- the **L4 tasks** final approval (Execute / Revise / Abort)

On each skipped gate, proceed with the derived result — a human already owns this bar
via decompose's single partition gate, where they approved the module boundaries,
shared decisions, and dependency edges for the whole set.

**What STILL runs in batch mode — every gate + derivation (nothing else is skipped):**
- **L1 codebase research** (L1 has no prompt; runs unchanged).
- **L2 / L3 / L4 derivation** from the partition context — decisions, requirements,
  and tasks are still fully derived; only the human approval prompt is skipped.
- the per-spec **L2-reviewer** subagent — specify's within-spec maker ≠ checker
  (complexity / coverage / vague-decision / cross-decision-tension / steelman). It is
  a checker subagent, not a human prompt, so it is **not** skipped.
  `coherence-audit` is a *cross*-spec checker and does **NOT** substitute for this
  *within*-spec L2-reviewer, so every generated spec keeps its own adversarial review.
- self-validation at every layer transition (the coverage / GWT / DAG gates).

**Partition context — where the batch inputs come from.** `decompose` points specify
at the approved manifest entry (`specs/<set>/partition-manifest.md`). In batch mode
specify inherits that entry's `## Shared Decisions` (`SD<n>`) **verbatim** into the top
of the spec's `## Decisions`, then derives the feature's local decisions below them;
and it emits the `## Declared Surface` section (declared-surface globs + `depends_on`)
from the manifest entry — per the T1 contract
(`skills/coherence-audit/references/declared-surface-schema.md` §1–§3). Batch mode's
deliverable is the written `spec.md` only: it does **NOT** trigger L4's execution
handoff (the caller — decompose, then build-order — owns execution).

---

## Handoff Mode — additive, opt-in suppression of the L4 execution handoff

specify gains ONE additive, opt-in marker that changes what happens **after** the final
approval — never the derivation, never a gate. A bare invocation is byte-unchanged.

**Marker.** `handoff: none` in the invocation args.

**What changes — exactly two things:**
1. The L4 final-approval option reads **"Approve"** ("Record approval and return to the
   caller") instead of **"Execute"** ("Start implementation via agent-orchestrate").
2. On approval, specify writes `Approved by:` / `Approved at:` to the spec's Meta section
   as usual and then **stops**, returning `{specDir}/spec.md` to its caller. The
   `Skill(skill="harness-ops:agent-orchestrate")` handoff in
   `references/L4-tasks.md` › `### Handoff to Execution` is **not** invoked.

**What does NOT change.** Every L0–L4 gate, every self-validation, the L2-reviewer, and
the written spec are identical. `handoff: none` is **not** an approval bypass — the human
still confirms the L0 mirror and approves at L2, L3 and L4. It removes the handoff only.

**Why this exists.** A caller that owns the steps *after* the spec — one that runs its own
review gate and ledger once `spec.md` exists — cannot let L4 launch `agent-orchestrate`,
because that would stamp approval and start execution before the caller's own gates run,
and would ask the human to approve twice. Batch mode already suppresses this same handoff
(`## Batch Mode`; `references/L4-tasks.md` › Final Approval); `handoff: none` makes that
suppression available to callers that still want the interactive gates.

**Composition with batch mode.** The two markers are independent and do not conflict.
Batch mode already does not hand off, so `mode: batch` + `handoff: none` is consistent
(the second marker is redundant there, not contradictory). `handoff: none` alone skips no
gate; `mode: batch` alone still skips exactly the gates it always did.

---

## Checklist Before Stopping

- [ ] spec.md at `{specDir}/spec.md` (resolved per `## Spec Directory`)
- [ ] `## Goal` section populated
- [ ] `## Confirmed Goal` section populated
- [ ] `## Non-goals` section populated (or "(none)")
- [ ] `## Research` section populated
- [ ] `## Decisions` section populated with at least one decision
- [ ] `## Constraints` section populated (or "(none)")
- [ ] `## Requirements` section with every requirement having at least 1 sub-requirement with GWT
- [ ] `## Tasks` section with every task having `Fulfills` linking to requirements
- [ ] Plan Summary presented to user
- [ ] `Approved by` and `Approved at` written to Meta section after final approval
- [ ] Handoff resolved: handed off to agent-orchestrate on Execute, OR returned to the
      caller with no handoff under `handoff: none` / batch mode
