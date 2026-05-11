# Harness Engineering Checklist (v3)

> The craft of designing environments where AI works well — **6 axes · 24 items**
>
> Axes are ordered as a "cycle": **Scaffolding → Context → Planning → Execution → Verification → Compounding** → (back to Scaffolding). Each full cycle makes the harness more robust.

## 3 Maturity Levels

| Level | Name | Analogy |
|-------|------|---------|
| **L1** | Getting Started | Learning grammar from a textbook |
| **L2** | Making It Your Own | Writing your own text using that grammar |
| **L3** | Self-sustaining | Your writing style has settled in |

## Analysis Framework — 2×3 Matrix

|  | **Static** (set up) | **Behavioral** (doing) | **Δ/Growth** (accumulating) |
|---|---|---|---|
| **👤 User Scope** | 1. Scaffolding | 3. Planning · 4. Execution (shared) | 6. Compounding (shared) |
| **📁 Project Scope** | 2. Context | 4. Execution (shared) · 5. Verification | 6. Compounding (shared) |

All judgments come from the **gap between what is set up and what is actually done**, or **whether the harness is growing**.

---

## Axis 1 — Scaffolding · 👤 User × Static [5 items]

> "What has been installed?" — Are installed skills/plugins/MCP organized and actually used?

| # | Check Item | L | Why It Matters | Judgment Basis (PORTFOLIO) |
|---|-----------|:-:|----------------|---------------------------|
| A1 | 70%+ of installed skills used in last 30 days | L1 | More unused skills → higher chance AI triggers the wrong skill | `used_last_30d / total_installed ≥ 0.7` |
| A2 | No dead skills (90d+ unused or usageCount=0) | L2 | Dead skills act as noise in trigger matching, wasting context | `dead_count == 0` |
| A3 | No ghost entries (usage record only, not installed) | L2 | History/reality mismatch → confusion during analysis/recovery | `ghost_count == 0` |
| A4 | No duplicate skill clusters (multiple skills with same intent) | L2 | AI picks a different skill each time → reproducibility↓, improvements don't accumulate | `duplicate_clusters == 0` |
| A5 | No prefix duplicates / trigger collisions | L3 | 2+ skills matched by same keyword → wrong skill executes | `prefix_duplicates == 0 && trigger_collisions == 0` |

---

## Axis 2 — Context · 📁 Project × Static [6 items]

> "What does the AI know?" — Is project knowledge (CLAUDE.md·rules·MCP etc.) progressively exposed?

| # | Check Item | L | Why It Matters | Judgment Basis (CONTEXT) |
|---|-----------|:-:|----------------|--------------------------|
| C1 | CLAUDE.md exists & includes project purpose/structure | L1 | Without it, repeat the same explanation every session — wasting tokens and time | `has_claude_md && has_project_purpose` |
| C2 | CLAUDE.md quality — no contradictions/ambiguity/placeholders | L1 | Contradictory instructions confuse AI, leading to arbitrary interpretation | `quality.contradictions == 0 && quality.ambiguities == 0` |
| C3 | Sensitive file protection — `.gitignore` + PreToolUse hook | L1 | Exposing .env secrets causes incidents → must block proactively | `sensitive_protection.gitignore && sensitive_protection.hook_exists` |
| C4 | Rules separated — `.claude/rules/` has ≥ 2 files with distinct scopes | L2 | Prevents CLAUDE.md bloat; role-based loading improves context efficiency | `rules_count ≥ 2 && rules_have_distinct_scope` |
| C5 | External system connected — MCP server configured | L2 | Direct access to DB/API → judgment based on facts instead of code | `mcp_configured` |
| C6 | Progressive Disclosure — conditional loading (glob/skill) | L3 | Always loading all rules explodes context; load only when needed | `conditional_load_evidence ≥ 1` |

---

## Axis 3 — Planning · 👤 User × Behavioral [1 item]

> "Do you plan first?" — Do you use spec/plan·AskUserQuestion to eliminate ambiguity before saying "go"?

| # | Check Item | L | Why It Matters | Judgment Basis (SESSION) |
|---|-----------|:-:|----------------|--------------------------|
| B2 | Plan before execute — use specify/scaffold/plan skills | L2 | The quality gap between "start coding immediately" vs "plan first then execute" is large | `plan_first_ratio ≥ 0.3 OR planning_artifacts_exist` (artifact fallback requires Project scope) |

---

## Axis 4 — Execution · 👤+📁 × Behavioral [3 items]

> "How do you assign work?" — Solo vs delegating to subagents, how is work arranged via team·subagent·orchestration?

| # | Check Item | L | Why It Matters | Judgment Basis (SESSION) |
|---|-----------|:-:|----------------|--------------------------|
| B3 | Delegation usage — sessions with Agent calls | L2 | Protects main context + improves both speed and quality through parallelization | `delegation_ratio ≥ 0.4` |
| B5 | Parallel execution — `run_in_background=true` usage | L3 | Running independent tasks sequentially wastes time | `parallel_count ≥ 1` |
| B6 | Repetitive request automation rate — top-5 tool 3-gram under 30% of total | L3 | Same tool pattern repeated = automation opportunity to extract as skill/hook | `top_ngram_share < 0.3` |

> This axis is computed for both User global sessions and Project-specific sessions. Report shows **both User and Project values side by side**.

---

## Axis 5 — Verification · 📁 × Static+Behavioral [6 items]

> "How do you trust the output?" — Use criteria, separated perspectives, and independent verifiers to avoid self-deceiving.

| # | Check Item | L | Why It Matters | Judgment Basis |
|---|-----------|:-:|----------------|----------------|
| B1 | Completion criteria met — test/ralph runs before session ends | L1 | Ending without verification leaves only the illusion of "done" and increases rework cost | SESSION: `completion_check_ratio ≥ 0.5` |
| D1 | Test environment — script or test framework | L1 | Without a verification tool, AI output quality cannot be confirmed | AUTOMATION: `test_runner_configured` |
| D2 | Formatter/linter auto-applied — PostToolUse hook | L1 | Manual format instructions every time = repeated cost; one hook solves it | AUTOMATION: `posttool_format_hook` |
| D3 | Dangerous actions blocked — PreToolUse hook exists | L1 | Safety net against mistakes like rm -rf, force push | AUTOMATION: `pretool_block_hook` |
| D4 | Project skills/hooks actually used — confirmed called in sessions | L2 | Built but not used has no value; verify actual usage | AUTOMATION: `project_skills_used ≥ 1` |
| D5 | Creator/verifier AI separated — verifier agent exists | L3 | Same AI implementing and verifying creates confirmation bias; separation stabilizes quality | AUTOMATION: `verifier_agent_exists` |

---

## Axis 6 — Compounding · 👤+📁 × Growth [3 items + 1]

> "How do you improve?" — Does what's learned in sessions flow back into harness artifacts (SKILL·Docs·CLAUDE.md) and accumulate?

| # | Check Item | L | Why It Matters | Judgment Basis |
|---|-----------|:-:|----------------|----------------|
| E1 | At least one of CLAUDE.md/rules/docs updated in last 30 days | L1 | If config is never updated, learning doesn't accumulate | AUTOMATION: `compounding.claude_md_updated_30d OR rules_added_90d>0 OR docs_learnings_exist` |
| B4 | Session handoff — session-wrap/memory write evidence | L2 | Without handoff, next session repeats the same explanations | SESSION: `handoff_ratio ≥ 0.5` (among long sessions) |
| E2 | session-wrap / compound / memory-write type used ≥1 time | L2 | Session learning must be externally recorded to be usable in the next session | SESSION: `skills_invoked` includes wrap/compound/memory-type calls |
| E3 | New skill·hook·rule added to project in last 90 days | L3 | Improvement must crystallize into an artifact to achieve L3 (self-sustaining) | AUTOMATION: `compounding.skills_added_90d ≥ 1 OR hooks_added_90d ≥ 1` |

---

## Judgment Status

| Status | Meaning |
|--------|---------|
| **PASS** | Evidence-based condition met |
| **WEAK_PASS** | Condition met but quality is low (Quick Win candidate) |
| **FAIL** | No evidence or explicit failure |
| **N/A** | Not applicable to project type or unable to collect evidence |

Score calculation: PASS=1, WEAK_PASS=0.5, FAIL=0, N/A=excluded · Weights: L1×3, L2×2, L3×1

---

## Maturity Achievement Rules

- **Per-axis level**: All L1 items for that axis PASS → L1 achieved; all L2 also PASS → L2; L3 also → L3
- **User Maturity**: lowest level among axes 1 · 3 · 4(User portion) · 6(User portion)
- **Project Maturity**: lowest level among axes 2 · 4(Project portion) · 5 · 6(Project portion)

---

## Signals That Things Are Going Well

- You don't repeat yourself (context accumulates)
- Mistakes become rules (improvement loop — axis 6)
- Unused skills keep shrinking (scaffolding cleanup — axis 1)
- New sessions need less explanation time (context quality — axis 2)

## Warning Signs That Things Are Going Wrong

- Config files only ever grow longer (context bloat)
- You re-edit half of AI output (verification absent)
- You don't use the automation you built (dead skills in scaffolding)
- You explain everything from scratch every session (handoff/compounding failure)

---

## Glossary

| Term | Definition |
|------|-----------|
| **Harness** | The environment built for AI to work well — the total of skills·hooks·rules·context. |
| **Skill** | A reusable prompt+logic collection triggered in specific situations. Defined in `SKILL.md`. |
| **Plugin** | A distribution unit bundling skills·hooks·agents·commands. |
| **Hook** | A script that auto-executes on specific events (PreToolUse, PostToolUse, Stop, etc.). |
| **Agent** | A subordinate AI running in an independent context. |
| **MCP** | Model Context Protocol. The standard for AI to directly access external systems. |
| **CLAUDE.md** | AI instruction file placed at the project root. |
| **Dead skill** | A skill with 0 calls in 90+ days. |
| **Ghost entry** | A usage record that exists but the skill is not actually installed. |
| **Trigger collision** | A situation where 2+ skills match the same keyword. |
| **Progressive Disclosure** | The "load only when needed" principle. |
| **Plan-first ratio** | The ratio of sessions where specify/scaffold/plan skills were used to plan before starting. |
| **Handoff** | Recording state to memory/CLAUDE.md/session-wrap at session end so the next session can pick up. |
| **Compounding** | Learning from sessions flowing back into SKILL·rules·docs so the harness grows. |
| **Verifier agent** | An agent that verifies independently. Mitigates confirmation bias. |

---

*Total 24 items (6 axes) | L1: 9 items, L2: 9 items, L3: 6 items*
