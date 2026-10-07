## Spec Review — fresh-context check before Final Approval

**Output**: Append (or replace) a `## Spec Review` section in spec.md

Runs after the L4 Gate and before the Plan Summary, in interactive and unattended runs.
Batch mode (`mode: batch` with `pre-approved-batch: yes`) skips it: decompose's
`coherence-audit` checks the set, and batch behaviour stays unchanged.

**No subagent tool** (the `Agent` tool is unavailable): an unattended run stops here
(report + notify, as for a final NEEDS_FIX); an interactive run records
`Verdict: not run (no subagent tool)` and says so in the Plan Summary. specify never
reviews its own spec in place of the reviewer.

### Why a fresh context

The model that wrote the spec remembers what each line was *meant* to say, so it reads
gaps as filled. The reviewer is a subagent with an empty context: it gets the spec path
and the checklist, never the interview, the user's answers, or specify's reasoning. It
judges what the file says, the way an engineer picking it up next week would. The
reviewer only reports; specify makes every edit (maker ≠ checker, as with L2-reviewer).

### Spawn the reviewer

```
Agent(subagent_type="general-purpose", prompt="""
You are reviewing an implementation spec before anyone builds from it. You did not
write it and have no other context about it. Judge only what the file says.

Read {specDir}/spec.md. Read repository files when a check needs them.
Do not edit, create, or delete any file.

Checks:
1. Coverage — every requirement is fulfilled by at least one task, and every task
   fulfills at least one requirement.
2. Testability — every Given/When/Then could be checked by a test or a command;
   flag any Then that is not observable.
3. Grounding — every file, function, command, and config key the spec names exists
   in the repository, or a task explicitly creates it.
4. Task order — no cycles, every `Depends on` names a real task, and tasks marked
   `parallel with` do not modify the same files.
5. Consistency — no task contradicts a Decision or Constraint, and none builds a
   Non-goal.
6. Readiness — an engineer with only this spec and the repo could start each task
   without asking a question.

Only report an issue you can point at in the spec or the repository. Wording
preferences are not issues.

Tasks marked `Fenced:` and Known Gaps that start with `L2 fenced:` are deliberately
left for a person to decide. Do not report an issue whose only cause is that deferral
(for example, a fenced task that cannot start yet). Do report other problems in
those tasks.

Return exactly this shape:
VERDICT: PASS | NEEDS_FIX
ISSUES:
- [check name] {location, e.g. T3 or R2.1} — {problem} — {suggested fix}
(or "ISSUES: none")
""")
```

### Fix loop

- **PASS** → record the result and continue to the Plan Summary.
- **NEEDS_FIX** → specify applies the fixes with Edit. If a fix touched `## Requirements`
  or `## Tasks`, re-run the L3 Gate and L4 Gate checks. Then spawn a **new** reviewer
  (a fresh context again, never a continuation of the last one). At most 2 re-reviews,
  so 3 reviews in total.

**What a fix may change:**
- **Interactive** — Tasks, `Depends on`, External Dependencies, file paths, and wording.
  It must not change a Decision or Requirement the user approved at L2 or L3; leave such
  an issue open for the Final Approval gate.
- **Unattended** (see specify `SKILL.md` › `## Unattended Mode`) — also Decisions and
  Requirements, since none were approved by a person. Mark a changed decision
  `Status: assumed`. Never resolve a fenced checkpoint (`L2 fenced:` in Known Gaps).

**After the last review:**
- **Interactive** — list open issues in the Plan Summary; the Final Approval options
  already include "Revise requirements (L3)" and "Revise tasks (L4)".
- **Unattended** — if the verdict is still NEEDS_FIX, stop before execution: do not hand
  off. Write the report and notify (Unattended Mode › Stop conditions).

### Record in spec.md

```markdown
## Spec Review
- **Verdict**: PASS | NEEDS_FIX
- **Reviews**: {n}
- **Fixed**:
  - [{check}] {location} — {what changed}
- **Open**:
  - [{check}] {location} — {problem}
  (or "(none)")
```
