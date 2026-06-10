---
name: agent-orchestrate
argument-hint: ""
description: |
  Analyze the user's task and propose the optimal orchestration pattern, then execute it.
  4 patterns: Sequential Pipeline, Parallel Subagent, Team Mode, Ralph Loop.
  Situation-aware pattern selection with user confirmation before execution.
  Use when: "/agent-orchestrate", "agent-orchestrate", "orchestration",
  "which pattern", "run in parallel", "run sequentially", "team mode", "agent pattern", "suggest execution pattern",
  "how should we run this", "pick a pattern".
  Also trigger when the user describes a complex multi-step task that would clearly
  benefit from agent coordination — e.g., "analyze companies A, B, C", "design, implement, and review",
  "do these in order", "run 3 at once", or any task with 3+ subtasks
  where choosing the right execution pattern matters for efficiency.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Agent
  - Task
  - AskUserQuestion
  - Skill
  - SendMessage
  - TeamCreate
  - TeamDelete
---

# /agent-orchestrate — Situation-Aware Agent Orchestration

Analyze the user's task, recommend the best orchestration pattern, and execute it upon approval.

---

## 4 Orchestration Patterns

| Pattern | When | Mechanism | Best For |
|---------|------|-----------|----------|
| **Sequential Pipeline** | Steps depend on each other (A→B→C) | TaskCreate → execute one by one | Blog writing, migration, ordered workflows |
| **Parallel Subagent** | N independent tasks, results merged | Agent × N spawn → main collects | Competitor analysis, multi-file review, bulk processing |
| **Team Mode** | Roles need inter-agent communication | TeamCreate → agents talk directly | Design+implement+review, complex features |
| **Ralph Loop** | Clear done-criteria, iterative refinement | Activate `harness-ops:loop` with a gate contract | Bug fixing to spec, quality gates, polish tasks |

---

## Phase 1: Task Analysis

When the user provides a task (as argument or in conversation):

### 1.1 Extract Signal

Read the task description and identify:

```
signals = {
  step_count:      how many distinct steps/subtasks?
  dependencies:    are steps dependent (A→B) or independent (A∥B)?
  parallelizable:  how many tasks can run simultaneously?
  roles_needed:    does the task need distinct roles (designer, implementer, reviewer)?
  inter_comm:      do workers need to communicate with each other mid-task?
  done_criteria:   is there a clear, binary definition of done?
  iterative:       does the task likely need multiple passes to get right?
  verification_source: where did the done-criteria come from?
                   `spec ({path})`            — the task args reference a spec.md path (e.g. specs/*/spec.md)
                   `done-criteria ({summary})` — the user stated explicit, measurable completion criteria
                                                 (e.g. "all tests pass", "p95 under 200ms")
                   `none`                      — neither of the above
}
```

### 1.2 Pattern Selection Logic

The key insight: check structural signals (parallelism, roles) first, then refinement signals (iteration).
Ralph is for tasks where the *primary challenge* is "getting it right" through iteration, not for any task that happens to have success criteria.

```
recommend_pattern =
  IF parallelizable >= 2 AND no inter_comm needed:
    "Parallel Subagent"
  ELIF roles_needed >= 2 AND inter_comm needed:
    "Team Mode"
  ELIF step_count >= 2 AND all dependencies are sequential (A→B→C):
    "Sequential Pipeline"
  ELIF done_criteria is clear AND iterative AND step_count <= 2:
    "Ralph Loop"
  ELIF step_count == 1:
    "Sequential Pipeline"  # simplest default for single task
  ELSE:
    "Parallel Subagent"    # safe default for multi-task
```

**Why Ralph is checked later**: Most multi-step tasks benefit from structural parallelism even if they have clear done-criteria. Ralph shines when the task is focused (1-2 subtasks) but needs iterative refinement to meet quality — e.g., "fix this bug until tests pass", "bring latency under 200ms".

---

## Phase 2: Propose to User

Present the recommendation using AskUserQuestion. Include:

1. **Why this pattern** — 1-2 sentence reasoning based on signals
2. **Execution plan preview** — what agents/tasks will be created
3. **All 4 options** — let the user override

### AskUserQuestion Format

```
question: "I recommend the '{recommended}' pattern for this task. {reason}. Which pattern would you like to use?"
header: "Pattern"
options:
  - label: "{recommended} (Recommended)"
    description: "{why this fits}"
  - label: "{2nd best}"
    description: "{when this would be better}"
  - label: "{3rd}"
    description: "{description}"
  - label: "{4th}"
    description: "{description}"
```

After pattern selection, present the execution plan preview:

```
question: "Here is the execution plan. Proceed?"
header: "Confirm"
options:
  - label: "Proceed"
    description: "{plan summary}"
  - label: "Revise then proceed"
    description: "I want to adjust the plan"
```

**If "Revise then proceed" is selected**: Ask "What would you like to change?" as an open question via AskUserQuestion. Incorporate the user's feedback, reconstruct the execution plan, then re-present the confirmation. If the user wants to change the pattern itself, return to the pattern selection step in Phase 2.

### Verification Gate Disclosure

When `verification_source != none` AND the selected pattern is **not** Ralph Loop, the execution plan preview MUST state all three of the following:

1. **Gate exists** — after execution, a verification gate will run via the `harness-ops:loop` skill against the spec / done-criteria.
2. **Gate auto-fixes** — if the gate fails, the loop will **modify code** within its Auto-fix autonomy boundary. It is not report-only.
3. **Opt-out** — the user can exclude the verification gate via "Revise then proceed".

If the user opts out of verification this way, Phase 3.5 is skipped and the Phase 4 Verification field records `declined — user opted out at Phase 2`.

---

## Phase 3: Execute by Pattern

### Pattern A: Sequential Pipeline

```
1. Parse task into ordered steps
2. FOR each step:
     TaskCreate(title=step.name, description=step.detail)
3. FOR each task in order:
     Execute the task directly (read, write, bash, etc.)
     TaskUpdate(status="completed")
4. Output: summary of all completed steps
```

**Key rule**: Each task must complete before the next begins. Pass outputs forward as context.

### Pattern B: Parallel Subagent

```
1. Parse task into independent subtasks
2. Spawn Agent per subtask (all in ONE message for true parallelism):
   Agent(
     description="subtask summary",
     prompt="full context + specific subtask + output format",
     subagent_type=<appropriate type or general-purpose>
   )
3. Collect all agent results
4. Synthesize/merge results into final output
5. Present unified result to user
```

**Key rule**: All agents must be spawned in a single message. The main agent does the synthesis — never delegate merging to a subagent.

### Pattern C: Team Mode

```
1. Define roles from task analysis (e.g., designer, implementer, reviewer)
2. TeamCreate with role-based agents:
   TeamCreate(
     agents=[
       {name: "role-1", description: "...", tools: [...]},
       {name: "role-2", description: "...", tools: [...]}
     ]
   )
3. Orchestrate via SendMessage:
   - Kick off first role's work
   - Route outputs between roles
   - Coordinate handoffs
4. TeamDelete when complete
5. Present final result
```

**Key rule**: Define clear handoff points. The orchestrator (you) coordinates — agents talk through you or directly via SendMessage.

### Pattern D: Ralph Loop

**Do NOT reimplement the loop.** Activate the `harness-ops:loop` skill, which owns the gate contract + verification machinery.

```
1. Formulate the task as a loop request:
   - Clear goal statement
   - Any done-criteria / thresholds the user provided
2. Invoke: Skill(skill="harness-ops:loop", args="{task description with context}")
3. The loop skill handles the rest:
   - Phase 0: gate contract (loop.md) proposal + user confirmation
   - Phase 1-3: Work → Verify (3 gates) → Fix, until gates pass or a boundary escalates
   - Phase 4: evidence report
```

**Key rule**: Pass through all relevant context (file paths, requirements, constraints) in the args so the loop has the full picture. Do not pre-define the gates — let the loop skill propose the contract.

---

## Phase 3.5: Verification Gate

specify's L4 omits a final-verify task because "holistic verification is handled in the execute pipeline" — this phase is that verification.

### When to Run

| Condition | Action |
|-----------|--------|
| Ralph Loop pattern was executed | Skip — report `embedded in Loop pattern — see Loop Report` (the gates already ran inside the pattern) |
| `verification_source: none` | Skip — report `skipped — no spec/done-criteria` |
| User opted out at Phase 2 | Skip — report `declined — user opted out at Phase 2` |
| Otherwise (non-Loop pattern + `verification_source` present) | Run the gate |

### How to Run the Gate

Invoke `Skill(skill="harness-ops:loop", args=...)`. The args MUST include:

1. The spec path (or the done-criteria)
2. Context of what was just executed — which tasks, which files
3. The explicit framing: **"implementation is already complete — start by verifying, do not redo the work"** (the loop's cycle starts at WORK; this framing makes iteration 1's work a no-op so VERIFY is effectively the first action)
4. Direction that the `loop.md` contract lives in the spec directory

The args must NOT pre-define the concrete gates — loop's Phase 0 owns gate derivation and contract approval (same ownership rule as Pattern D).

### Failure Handling

- **User rejects the contract at loop's Phase 0** → record `aborted — contract rejected at Phase 0`. Verification is honestly recorded as not performed — never as passed.
- **The Skill invocation itself errors** → relay the error in the report and suggest running `/harness-ops:loop` manually with the spec path.

---

## Phase 4: Report

After execution completes (regardless of pattern), output a brief summary:

```markdown
## Orchestration Complete

**Pattern**: {chosen pattern}
**Tasks**: {count} completed
**Result**: {1-3 sentence summary of what was done}
**Verification**: {one of the states below}
```

**Verification** is mandatory and must be exactly one of:

| State | Meaning |
|-------|---------|
| `passed (N iterations)` | All loop gates passed — attach a brief Evidence Report summary |
| `escalated: {reason}` | Loop hit an autonomy boundary or made no progress |
| `embedded in Loop pattern — see Loop Report` | Ralph Loop pattern ran; the gates were inside the pattern |
| `skipped — no spec/done-criteria` | `verification_source: none` — gate not applicable |
| `declined — user opted out at Phase 2` | User excluded verification via "Revise then proceed" |
| `aborted — contract rejected at Phase 0` | User rejected the loop contract — verification not performed |

When the state is `escalated` or `aborted`, the report must not claim success anywhere.

---

## Rules

1. **Always ask before executing** — never skip Phase 2 confirmation
2. **Ralph Loop is a skill call, not a reimplementation** — use `Skill(skill="harness-ops:loop")`
3. **Parallel agents in one message** — don't spawn sequentially
4. **Match pattern to situation** — don't force a pattern; if the task is trivial, sequential is fine
5. **Pass context forward** — each step/agent needs enough context to work independently
6. **Keep proposals concise** — the user wants a recommendation, not an essay
7. **Relay the verification verdict as-is** — never fabricate or soften a failing verdict into success
8. **The verification gate never runs twice** — the Ralph Loop pattern embeds it; Phase 3.5 skips in that case
9. **Disclose auto-fix in Phase 2** — the preview must state that the gate modifies code on failure, not just reports
