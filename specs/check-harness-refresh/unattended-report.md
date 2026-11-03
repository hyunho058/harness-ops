> **Superseded 2026-11-02.** At the user's request the 5 open items below were fixed, the spec was approved by the user, and the plan was executed interactively via agent-orchestrate (Parallel Subagent) with a passing harness-ops:loop verification gate (2 iterations). This file is kept as the record of the unattended stop.

# Unattended specify run — stopped before execution

- **Spec**: `specs/check-harness-refresh/spec.md`
- **Branch**: `fix/check-harness-refresh` (worktree `harness-ops-fix-check-harness-refresh`); nothing committed, nothing pushed
- **Stopped at**: L4 Spec Review — the fix confirmation (after 3 full reviews) returned **NEEDS_FIX**. Unattended rules stop here: `Approved by` was not written, and agent-orchestrate was not invoked. No code was changed.
- **Marker**: the invocation ended with `mode : unattened`; it was read as `mode: unattended` (recorded as inferred in the spec's Confirmed Goal).

## Why it stopped
The fix confirmation found 5 remaining issues, 4 of them introduced by the last round of fixes. All are about the new `params` / script-output plumbing, and all are text-level contract gaps:
1. D5 / T4: `params` missing from `inventory.py`'s output key list.
2. D7 / D9 / T5 / R8.2: `--with-params` missing from `session_files.py`'s signature; D9 doesn't say `session_metrics.py` skips a `# params` line and echoes it; session-pattern-analyzer isn't told to pass the flag.
3. D15: `skills` scans `.claude/skills/*/SKILL.md` but D4/D5 use `.claude/skills/**/SKILL.md`.
4. D10: the "analyzer-owned" required keys include script-produced fields, and Phase 2's source for `checker_citations` / `unattended` / `project_skills.registered` isn't settled.
5. D1: `as_of_ms` isn't passed in any spawn prompt, so its `params` echo can't be checked.

## What was assumed
All 22 decisions are `Status: assumed`; there were no human answers. The main choices:
- deterministic collection moves into 6 tested Python scripts under `skills/check-harness/scripts/`, run by the analyzers (D1, D2);
- one alias table `skills/check-harness/references/skill-aliases.tsv` (D3, D4);
- one 30-day window everywhere (D8);
- unattended safety becomes a new L3 item, D6, in Axis 5, not a 7th axis, giving 26 items: L1 9 / L2 10 / L3 7 (D18, D19);
- a root `Makefile` `test` target plus run-tests.sh section E (D20);
- check-harness halts on agy only on a real negative, not on an empty registry (D13).

## What would be parked
Nothing. No task is in a fenced area (schema, data-loss migration, auth/permission, payment/secrets).

## Review history
- L2-reviewer: 3 rounds plus 2 more after spec fixes; every round's issues were applied.
- Spec Review: 3 full reviews (14, 9 and 7 issues, all applied), then the fix confirmation (5 open). Details are in the spec's `## Spec Review` section.

## Next step for you
Pick one:
- **Fix the 5 open items and execute** (recommended). They are small edits to D1, D5, D7, D9, D10 and D15 and to T4/T5. Then run, interactively:
  `/harness-ops:agent-orchestrate Implement the approved plan in specs/check-harness-refresh/spec.md` — after adding `- **Approved by**: user` to `## Meta` yourself.
- **Re-run specify interactively** on the existing spec: `/harness-ops:specify specDir: specs/check-harness-refresh/ …` to get the L2/L3/L4 approval gates.
