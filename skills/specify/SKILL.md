---
name: specify
argument-hint: ""
description: |
  Turn a goal into an implementation plan (spec.md).
  Simplified layer chain: L0:Goal → L1:Context → L2:Decisions → L3:Requirements → L4:Tasks.
  Evidence-based clarity scoring at L2. User approves at L2, L3, L4.
  A fresh-context reviewer checks the finished spec before the final approval.
  Opt-in `mode: unattended` runs the whole chain with no prompts, on its own branch.
  Output is a single spec.md file written with the Write tool.
  Use when: "/specify", "specify", "plan this"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Agent
  - Bash
  - Write
  - Edit
  - AskUserQuestion
  - Skill
  - PushNotification
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

The spec is written to a project-relative directory:

```
specs/{name}/spec.md
```

`{name}` = kebab-case derived from the goal.

Create the directory at Session Init:
```bash
mkdir -p specs/{name}
```

---

## Layer Flow

Execute layers sequentially. Read each reference file just-in-time.

| Layer | Read Reference | What | Gate |
|-------|----------------|------|------|
| L0 | `references/L0-L1-context.md` | Mirror → Goal, Non-goals, Confirmed Goal | User confirms mirror |
| L1 | (same file) | Codebase research → Research section | Auto-advance |
| L2 | `references/L2-decisions.md` | Interview → Decisions + Constraints | Self-validate + L2-reviewer + User approval |
| L3 | `references/L3-requirements.md` | Derive requirements + sub from decisions | Self-validate + User approval |
| L4 | `references/L4-tasks.md` | Derive tasks + external deps, Plan Summary | Self-validate + Spec Review (`references/spec-review.md`) + User approval |

### Session Init (before L0)

```bash
mkdir -p specs/{name}
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

> **Batch-mode bypass (opt-in, additive — see `## Batch Mode` below):** when specify
> is invoked with the marker `mode: batch` AND the feature's partition-manifest entry
> carries `pre-approved-batch: yes`, SKIP each of these three (L2 / L3 / L4)
> `AskUserQuestion` gates — and the L0 mirror confirmation — and proceed with the
> derived result (the human already owns the bar via decompose's ONE partition gate).
> A bare invocation with no marker runs every gate exactly as before.

> **Unattended bypass (opt-in, additive — see `## Unattended Mode` below):** when the
> user's own invocation carries `mode: unattended`, SKIP every `AskUserQuestion` in
> L0–L4, answer the L2 interview from evidence, and hand off to agent-orchestrate with
> the same marker. The fresh-context Spec Review becomes the gate before execution.

---

## Batch Mode — additive, opt-in bypass (mirrors loop's `pre-approved-unattended`)

specify gains ONE additive, opt-in batch path — the structural twin of loop's
`pre-approved-unattended` bypass (`skills/loop/SKILL.md:233-240, 453`). This batch
path adds nothing to the interactive L0–L4 core: a bare `/specify "goal"` with no
marker runs exactly the layers and gates it would run without this section.

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

(The fresh-context Spec Review, added later for interactive and unattended runs, does
not run in batch mode — `coherence-audit` checks the set instead. See
`references/spec-review.md`.)

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

## Unattended Mode — opt-in, no prompts (single task)

One request runs specify → Spec Review → agent-orchestrate → loop verification with no
human prompt. It is the single-task counterpart of batch mode: there the human approves
once at decompose's partition gate; here the human approves once by writing the marker
into their own request.

**Trigger.** The user's own invocation of specify carries `mode: unattended`. specify
never adds the marker to its own invocation, and no other skill passes it to specify.
Without the marker every gate runs exactly as before.

**Launch it in its own worktree:**

```
claude --bg -w <name> --permission-mode auto "/harness-ops:specify <goal> mode: unattended"
```

`--bg` returns immediately (`claude agents` lists the run, `claude logs <id>` shows its
output); `-w` gives the run its own git worktree and branch; `--permission-mode auto`
approves routine tool calls, while the auto-mode classifier can still refuse a risky one.

**Branch guard (Session Init, before anything is written).** Run
`git rev-parse --abbrev-ref HEAD` and stop, printing the launch command above, when:
- the directory is not a git repository;
- the result is the literal `HEAD` (detached checkout);
- the result is the default branch — `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`
  with the `origin/` prefix removed, or `main` / `master` when there is no remote HEAD.

An unattended run edits code nobody is watching; its own branch is what keeps that
reviewable and reversible.

**The fence.** Some work is never decided or done unattended: database schema changes,
migrations that can lose data, auth / permission / access-control policy changes, and
payment or security-sensitive changes (secrets, crypto, billing). This is loop's 🛑 STOP
list (`skills/loop/SKILL.md` › Autonomy Boundary), applied from the spec onward:
- L2 never answers a fenced checkpoint the request did not settle; it goes to Known Gaps
  as `L2 fenced: {area} — {checkpoint}`.
- L4 marks every task whose work falls in a fenced area with `- **Fenced**: {area} — {why}`.
- agent-orchestrate parks fenced tasks and everything that depends on them, runs the
  rest, and notifies.

**What changes per layer** (each reference file carries the matching paragraph):

| Layer | Interactive | Unattended |
|-------|-------------|------------|
| L0 | Mirror → user confirms | Mirror written as Confirmed Goal without asking; Meta gets `- **Mode**: unattended` |
| L1 | Auto | Unchanged |
| L2 | Interview → L2-reviewer → user approves | specify answers each question from the request, then the codebase, then its own best choice (`Status: assumed`); fenced checkpoints stay open; L2-reviewer still runs |
| L3 | User approves | Self-checks only |
| L4 | Spec Review → user approves Execute | Fenced tasks marked; Spec Review is the gate; on PASS add `- **Approved by**: unattended (request marker)` and hand off with `mode: unattended` |

**Marker chain.** agent-orchestrate and loop act unattended only when their invocation
carries the marker AND the spec file, which they read themselves, has both
`- **Mode**: unattended` and `- **Approved by**: unattended (request marker)` in `## Meta`. Write
both lines exactly in that form. A spec
from a run that stopped never gets the second line, so it cannot be executed unattended
later.

**Stop conditions.** The run ends without executing anything when:
- the branch guard fails;
- the request is too vague to state a goal with at least one checkable done criterion;
- the Spec Review can't run (no subagent tool) or still returns NEEDS_FIX after its last
  re-review;
- nothing would be left to run once every fenced task and every task that depends on
  one, directly or transitively, is set aside.

**Report and notify.** At each of these stops, write `{specDir}/unattended-report.md` —
why it stopped, what was assumed, what would be parked, the review verdict, the branch,
and the next step for the person — and send a `PushNotification` with a one-line
summary. If `PushNotification` is unavailable, the report file is the record. After the
handoff, agent-orchestrate owns the report and the final notification. A branch-guard
stop happens before `{specDir}` exists, so it only prints the reason and the launch
command.

**Never in this mode:** call `AskUserQuestion`, decide or implement fenced work, run on
the default branch, or push.

---

## Checklist Before Stopping

- [ ] spec.md at `specs/{name}/spec.md`
- [ ] `## Goal` section populated
- [ ] `## Confirmed Goal` section populated
- [ ] `## Non-goals` section populated (or "(none)")
- [ ] `## Research` section populated
- [ ] `## Decisions` section populated with at least one decision
- [ ] `## Constraints` section populated (or "(none)")
- [ ] `## Requirements` section with every requirement having at least 1 sub-requirement with GWT
- [ ] `## Tasks` section with every task having `Fulfills` linking to requirements
- [ ] `## Spec Review` section with the reviewer's verdict (interactive and unattended runs)
- [ ] Plan Summary presented to user
- [ ] `Approved by` and `Approved at` written to Meta section after final approval
- [ ] Unattended runs that stop before the handoff: `{specDir}/unattended-report.md` written and a notification sent
