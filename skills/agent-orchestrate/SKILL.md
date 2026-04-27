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
| **Ralph Loop** | Clear done-criteria, iterative refinement | Activate /ralph skill with DoD | Bug fixing to spec, quality gates, polish tasks |

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

**Do NOT reimplement ralph.** Activate the existing skill.

```
1. Formulate the task as a ralph-compatible request:
   - Clear goal statement
   - Implicit or explicit done-criteria the user provided
2. Invoke: Skill(skill="ralph", args="{task description with context}")
3. Ralph handles the rest:
   - Phase 1: DoD proposal + user confirmation
   - Phase 2: Work + Stop hook verification loop
```

**Key rule**: Pass through all relevant context (file paths, requirements, constraints) in the args so ralph has full picture. Do not pre-define DoD — let ralph propose it.

---

## Phase 4: Report

After execution completes (regardless of pattern), output a brief summary:

```markdown
## Orchestration Complete

**Pattern**: {chosen pattern}
**Tasks**: {count} completed
**Result**: {1-3 sentence summary of what was done}
```

---

## Rules

1. **Always ask before executing** — never skip Phase 2 confirmation
2. **Ralph is a skill call, not a reimplementation** — use `Skill(skill="ralph")`
3. **Parallel agents in one message** — don't spawn sequentially
4. **Match pattern to situation** — don't force a pattern; if the task is trivial, sequential is fine
5. **Pass context forward** — each step/agent needs enough context to work independently
6. **Keep proposals concise** — the user wants a recommendation, not an essay
