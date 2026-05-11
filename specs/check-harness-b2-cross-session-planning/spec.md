# Spec: check-harness-b2-cross-session-planning

## Meta
- **Created**: 2026-05-11
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-05-11

## Goal
Expand the B2 (plan_first_ratio) judgment criterion in check-harness so that projects which perform planning in a separate session (before implementation) are correctly recognized as PASS — not penalized for cross-session planning workflows.

## Non-goals
- Option B (rules override approach) — not pursuing
- Modifying any harness axes other than B2
- Changing the B2 threshold value (0.3 stays as-is)

## Confirmed Goal
Modify the B2 evaluation logic so PASS is awarded when EITHER:
1. `plan_first_ratio ≥ 0.3` (existing criterion), OR
2. Pre-existing files exist in `specs/` or `deep-interview-outputs/` that were created before the implementation session — indicating cross-session planning occurred.

The fix should be reflected in both the SKILL.md prose (the rubric description) and the actual evaluation agent that performs the B2 check.

## Decisions

### D1: B2 artifact fallback yields PASS (not WEAK_PASS); qualified by naming pattern
- **Status**: resolved
- **Rationale**: Artifact existence in `specs/` (matching `specs/*/spec.md`) or `deep-interview-outputs/` (matching `deep-interview-outputs/*/insights.md`) is treated as full PASS — identical to meeting `plan_first_ratio ≥ 0.3`. Naming pattern constraint mitigates false positives from unrelated files. Stale artifacts are explicitly accepted: the presence of these canonical files indicates the developer *habitually uses plan-first workflows*, regardless of whether planning occurred in the current session — consistent with how `docs_learnings_exist` treats directory presence as behavioral evidence. Rejected WEAK_PASS: would create a confusing two-tier system where the same work quality gets different labels depending on whether planning happened in-session vs. cross-session.

### D2: File existence is sufficient — no content threshold
- **Status**: resolved
- **Rationale**: Any file in the target directories passes. Rejected content-threshold approach: would require arbitrary size/line limits that are hard to tune and create false negatives for valid short specs.

### D3: planning_artifacts_exist stored in AUTOMATION.json
- **Status**: resolved (assumed)
- **Rationale**: `project-automation-auditor` already follows this exact pattern (`docs_learnings_exist` boolean). Adding `planning_artifacts_exist` there is consistent with the existing data collection architecture. The check-harness orchestrator already holds `AUTOMATION` in memory during Phase 2 judgment — no architectural change needed. Alternative (inline check in check-harness Phase 2) was rejected: duplicates filesystem detection logic that belongs in the auditor.

### D4: Artifact fallback only fires when AUTOMATION data is available
- **Status**: resolved
- **Rationale**: When running User-scope only (`/check-harness user`), no Project agents are spawned and `AUTOMATION.json` is absent — fallback silently cannot fire, and B2 judgment falls back to ratio-only. This is acceptable: User-scope-only runs are intentionally incomplete for project signals. Constraint: document this in checklist.md.

### D5: session-pattern-analyzer plan_first_ratio calculation unchanged
- **Status**: resolved (assumed)
- **Rationale**: The fallback is a judgment-layer override in check-harness Phase 2 — the session-pattern-analyzer metric is not modified. This minimizes blast radius and keeps the raw metric truthful.

### D6: Evidence string updated to distinguish artifact-based PASS
- **Status**: resolved (assumed)
- **Rationale**: When artifact fallback fires, evidence reads `"planning artifacts found: specs/ (N files)"` instead of `"plan_first_ratio: X"`. This makes the reason for PASS auditable in reports.

## Constraints
- Artifact fallback is only available when Project scope is included (requires `AUTOMATION.json`)
- `plan_first_ratio` metric in `SESSION_USER.json` must remain semantically unchanged
- Judgment-layer change only — no modification to session-pattern-analyzer output schema

## Tasks

### T1: Add planning_artifacts_exist detection to project-automation-auditor [infra]
- **Fulfills**: R1 (R1.1, R1.2, R1.3)
- **Depends on**: (none)
- **Files**: `agents/project-automation-auditor.md`
- **Work**: Add bash detection commands (`find specs -name spec.md 2>/dev/null | wc -l`, `find deep-interview-outputs -name insights.md 2>/dev/null | wc -l`) to Step 1 data collection. Add `planning_artifacts_exist: bool` to Step 3 output schema.

### T2: Update B2 judgment logic and evidence string in check-harness SKILL.md [vertical]
- **Fulfills**: R0, R2 (R2.1–R2.4), R3 (R3.1, R3.2)
- **Depends on**: (none) ← parallel with T1 and T3 (interface pre-agreed in spec: field name `planning_artifacts_exist`)
- **Files**: `skills/check-harness/SKILL.md`
- **Work**: In Phase 2 Axis 3 judgment: change B2 evaluation from single `plan_first_ratio ≥ 0.3` check to OR condition. Add guard for absent AUTOMATION (User-scope-only path). Update evidence string logic to emit artifact-based vs. ratio-based strings.

### T3: Update B2 rubric text in checklist.md [infra]
- **Fulfills**: R4 (R4.1)
- **Depends on**: (none) ← parallel with T1 and T2 (different file, no interface dependency)
- **Files**: `skills/check-harness/references/checklist.md`
- **Work**: Update B2 Judgment Basis column from `plan_first_ratio ≥ 0.3` to `plan_first_ratio ≥ 0.3 OR planning_artifacts_exist` with parenthetical scope note.

## External Dependencies

### Pre-work
(none)

### Post-work
(none)

## Known Gaps
(none)

## Requirements

### R0: B2 cross-session planning detection works end-to-end

#### R0.1: Full PASS path via artifact fallback
- **Given**: Project contains `specs/my-feature/spec.md`, and `plan_first_ratio` is 0.15
- **When**: `/check-harness` runs with Both (User+Project) scope
- **Then**: B2 status = PASS with evidence showing artifact count, not ratio value

---

### R1: project-automation-auditor outputs planning_artifacts_exist (D3)

#### R1.1: Detects qualifying specs/ file
- **Given**: Project root contains `specs/any-name/spec.md`
- **When**: project-automation-auditor runs step 1 data collection
- **Then**: `AUTOMATION.json` contains `"planning_artifacts_exist": true`

#### R1.2: Detects qualifying deep-interview-outputs/ file
- **Given**: Project root contains `deep-interview-outputs/any-topic/insights.md`
- **When**: project-automation-auditor runs step 1 data collection
- **Then**: `AUTOMATION.json` contains `"planning_artifacts_exist": true`

#### R1.3: Returns false when no qualifying files
- **Given**: Project root has no `specs/*/spec.md` and no `deep-interview-outputs/*/insights.md`
- **When**: project-automation-auditor runs
- **Then**: `AUTOMATION.json` contains `"planning_artifacts_exist": false`

---

### R2: check-harness Phase 2 evaluates B2 with artifact fallback (D1, D4, D5)

#### R2.1: Artifact fallback fires PASS when ratio below threshold
- **Given**: `SESSION_USER.metrics.plan_first_ratio = 0.15` and `AUTOMATION.planning_artifacts_exist = true`
- **When**: check-harness evaluates B2 in Phase 2
- **Then**: B2 status = PASS; evidence string references artifact count, not ratio

#### R2.2: Ratio condition still independently triggers PASS
- **Given**: `SESSION_USER.metrics.plan_first_ratio = 0.35` regardless of `planning_artifacts_exist`
- **When**: check-harness evaluates B2
- **Then**: B2 status = PASS; evidence string references `plan_first_ratio: 0.35`

#### R2.3: Both conditions false → FAIL
- **Given**: `plan_first_ratio = 0.10` and `AUTOMATION.planning_artifacts_exist = false`
- **When**: check-harness evaluates B2
- **Then**: B2 status = FAIL

#### R2.4: User-scope-only run → ratio-only judgment (D4)
- **Given**: `/check-harness user` run; `AUTOMATION.json` is absent (no Project agents spawned)
- **When**: check-harness evaluates B2
- **Then**: B2 judgment uses `plan_first_ratio` only; no artifact fallback attempted; no error raised

---

### R3: Evidence string identifies source of PASS (D6)

#### R3.1: Artifact-based evidence format
- **Given**: B2 passes via artifact fallback (`planning_artifacts_exist = true`)
- **When**: check-harness renders B2 evidence in the Axis 3 table
- **Then**: Evidence string reads `"planning artifacts found: specs/ (N files)"` where N is the file count

#### R3.2: Ratio-based evidence format unchanged
- **Given**: B2 passes via `plan_first_ratio ≥ 0.3`
- **When**: check-harness renders B2 evidence
- **Then**: Evidence string continues to read `"plan_first_ratio: X.XX"` as before

---

### R4: checklist.md rubric text updated to reflect new criterion (D1, D4)

#### R4.1: Judgment basis column reflects OR condition
- **Given**: `checklist.md` B2 row currently shows only `plan_first_ratio ≥ 0.3`
- **When**: developer or check-harness reads the judgment basis
- **Then**: Text reads `plan_first_ratio ≥ 0.3 OR planning_artifacts_exist` with a note that artifact fallback requires Project scope

## Research

- B2 judgment basis defined at `skills/check-harness/references/checklist.md:61` — `plan_first_ratio ≥ 0.3` (single condition, no fallback)
- `plan_first_ratio` calculated in `agents/session-pattern-analyzer.md:77` — "Ratio of sessions containing `Skill(specify/scaffold/plan/deep-interview)` or plan mode" (session-JSONL-only, no filesystem access)
- Axis 3 data source mapped in `skills/check-harness/SKILL.md:175` — sources `SESSION_USER`, judgment field `plan_first_ratio (B2)` only
- `project-automation-auditor.md:83` already has `docs_learnings_exist` boolean pattern — same `ls dir/ 2>/dev/null` directory existence check style
- `skills/specify/SKILL.md:43` — spec artifacts written to `specs/{name}/spec.md`
- `skills/deep-interview/SKILL.md:331` — interview artifacts written to `deep-interview-outputs/[topic-slug]/insights.md`
- No existing `specs/` or `deep-interview-outputs/` detection anywhere in check-harness or project-automation-auditor
- check-harness Phase 1 loads all JSON reports (including `AUTOMATION`) into memory before Phase 2 judgment — `AUTOMATION` is accessible when evaluating B2
