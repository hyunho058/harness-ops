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
1. Coverage — every requirement is fulfilled by at least one implementation task. A
   `TTn` task does not count toward that: its tests check Rn, and nothing builds it.
   Separately, every task fulfills at least one requirement — a `TTn` included, whose
   `Fulfills: Rn (tests)` counts for this half.
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
- **NEEDS_FIX** → specify applies the fixes it is allowed to make (below) with Edit.
  Re-run the gates a fix touched: `## Decisions` → the L2 Gate and the L2-reviewer
  (the only adversarial check on decisions, and a changed decision can invalidate the
  requirements derived from the old one); `## Requirements` → the L3 Gate; `## Tasks`
  → the L4 Gate. **Only if at least one fix was applied**, spawn a **new** reviewer
  (a fresh context again, never a continuation of the last one). If nothing could be
  changed — every remaining issue is one specify must not fix — record those issues as
  Open now and skip to "After the last review"; a re-review of an unchanged file
  returns the same verdict. At most 2 re-reviews, so 3 reviews in total; an unattended
  run may add one scoped fix confirmation after them (below).
- Keep the verdict, issue list, and fixes in working notes until the loop ends. Do not
  write `## Spec Review` into spec.md between rounds: the next reviewer reads the whole
  file, and a previous verdict with "Fixed" entries would anchor it on re-checking
  those items instead of judging the spec cold.

**What a fix may change:**
- **Interactive** — Tasks, `Depends on`, External Dependencies, file paths, and wording.
  It must not change a Decision or Requirement the user approved at L2 or L3; leave such
  an issue open for the Final Approval gate.
- **Unattended** (see specify `SKILL.md` › `## Unattended Mode`) — also Decisions and
  Requirements, since none were approved by a person. Mark a changed decision
  `Status: assumed`. Never resolve a fenced checkpoint (`L2 fenced:` in Known Gaps).

**Fix confirmation (unattended only).** Fresh reviewers on a large spec rarely run out
of new findings, so three full reviews often end on NEEDS_FIX with every finding already
fixed but none of the fixes checked. When the third review returns NEEDS_FIX and specify
applied at least one fix after it (and re-ran the gates that fix touched), spawn one
more fresh reviewer, scoped to those fixes instead of the whole spec:

```
Agent(subagent_type="general-purpose", prompt="""
A reviewer found the issues below in {specDir}/spec.md, and the author then edited the
spec to fix them. You did not write it and have no other context about it.

Read {specDir}/spec.md. Read repository files when a check needs them.
Do not edit, create, or delete any file.

Issues and the fix applied to each:
{for each issue: [check] location — problem — what was changed}

For each issue: is it resolved by what the spec now says? Then: does any of those
changes contradict another part of the spec (a Decision, Requirement, GWT, task body,
or Depends on), or name a file, function, or command that neither exists nor is created
by a task? Do not review anything else, and do not report wording preferences.

Return exactly this shape:
VERDICT: PASS | NEEDS_FIX
ISSUES:
- [unresolved | introduced] {location} — {problem}
(or "ISSUES: none")
""")
```

It runs once and its result is final: specify does not edit after it. PASS → the
spec counts as reviewed, with Open `(none)`. NEEDS_FIX → its issues are the Open list.
It is skipped when the third review left nothing specify was allowed to fix. Interactive
runs don't use it, because the Final Approval gate is where a person settles open issues.

**After the last review:**
- **Interactive** — list open issues in the Plan Summary; the Final Approval options
  already include "Revise requirements (L3)" and "Revise tasks (L4)".
- **Unattended** — if the last verdict (the fix confirmation's, when it ran) is still
  NEEDS_FIX, stop before execution: do not hand off. Write the report and notify
  (Unattended Mode › Stop conditions). A fix that changes a Decision is not, by itself,
  a reason to stop or ask: unattended fixes may change Decisions (above), and a
  fenced checkpoint is never changed by a fix at all.

### Record in spec.md

Written once, after the final verdict (never between rounds — see Fix loop).

```markdown
## Spec Review
- **Verdict**: PASS | NEEDS_FIX
- **Reviews**: {n} (add `+ fix confirmation` when it ran; its verdict is the Verdict above)
- **Fixed**:
  - [{check}] {location} — {what changed}
- **Open**:
  - [{check}] {location} — {problem}
  (or "(none)")
```
