# Harness Engineering Checklist (v3)

> The craft of designing environments where AI works well — **6 axes · 26 items**
>
> Axes are ordered as a "cycle": **Scaffolding → Context → Planning → Execution → Verification → Compounding** → (back to Scaffolding). Each full cycle makes the harness more robust.
>
> **Field names.** A report name followed by a field means that report's field: `PORTFOLIO.summary.*`, `SESSION_*.metrics.*`, `SESSION_*.skills_invoked` / `commands_invoked` / `agents_invoked` and the `AUTOMATION` signals (`planning_artifacts`, `lessons`, `ledgers`, `skills`, `agents`, `checker_citations`, `unattended`, `compounding`) are script-owned and are read from that analyzer's fixed-path script output; every other field comes from the analyzer's saved return (`SKILL.md` › Phase 2 › Per-axis data source mapping). **Period:** every session-based item reads one 30-day window, for User and Project alike.

## 3 Maturity Levels

| Level | Name | Analogy |
|-------|------|---------|
| **L1** | Getting Started | Learning grammar from a textbook |
| **L2** | Making It Your Own | Writing your own text using that grammar |
| **L3** | Self-sustaining | Your writing style has settled in |

## Analysis Framework — 2×3 Matrix

|  | **Static** (set up) | **Behavioral** (doing) | **Δ/Growth** (accumulating) |
|---|---|---|---|
| **User Scope** | 1. Scaffolding | 3. Planning · 4. Execution (shared) | 6. Compounding (shared) |
| **Project Scope** | 2. Context | 4. Execution (shared) · 5. Verification | 6. Compounding (shared) |

All judgments come from the **gap between what is set up and what is actually done**, or **whether the harness is growing**.

---

## Axis 1 — Scaffolding · User × Static [5 items]

> "What has been installed?" — Are installed skills/plugins/MCP organized and actually used?

| # | Check Item | L | Why It Matters | Judgment Basis (PORTFOLIO) |
|---|-----------|:-:|----------------|---------------------------|
| A1 | 70%+ of installed skills used in last 30 days | L1 | More unused skills → higher chance AI triggers the wrong skill | `summary.used_last_30d / summary.total_installed ≥ 0.7` |
| A2 | No dead skills (90d+ unused or usageCount=0) | L2 | Dead skills act as noise in trigger matching, wasting context | `summary.dead_count == 0` |
| A3 | No ghost entries (usage record only, not installed) | L2 | History/reality mismatch → confusion during analysis/recovery | `summary.ghost_count == 0` (renamed history and built-ins are not ghosts) |
| A4 | No duplicate skill clusters (multiple skills with same intent) | L2 | AI picks a different skill each time → reproducibility↓, improvements don't accumulate | `duplicate_clusters` is empty |
| A5 | No prefix duplicates / trigger collisions | L3 | 2+ skills matched by same keyword → wrong skill executes | `summary.prefix_duplicates == 0 && trigger_collisions` is empty (name collisions ∪ same `"/xxx"` in two descriptions) |

---

## Axis 2 — Context · Project × Static [6 items]

> "What does the AI know?" — Is project knowledge (CLAUDE.md·rules·MCP etc.) progressively exposed?

| # | Check Item | L | Why It Matters | Judgment Basis (CONTEXT) |
|---|-----------|:-:|----------------|--------------------------|
| C1 | CLAUDE.md exists & includes project purpose/structure | L1 | Without it, repeat the same explanation every session — wasting tokens and time | `claude_md.exists && claude_md.has_project_purpose` |
| C2 | CLAUDE.md quality — no contradictions/ambiguity/placeholders | L1 | Contradictory instructions confuse AI, leading to arbitrary interpretation | One judge, the reviewer: `claude_md.quality.contradictions > 0` → FAIL; `contradictions == 0` but `drift_report` was generated within 30 days and lists `contradictions ≥ 1` → WEAK_PASS (evidence: `drift_report.path`); otherwise, with `contradictions == 0`: `ambiguities == 0 && placeholders == 0` → PASS, and `ambiguities ≥ 1` or `placeholders ≥ 1` → WEAK_PASS (evidence: the counts and the first `ambiguity_examples` entry). Only a contradiction fails C2 |
| C3 | Sensitive file protection — `.gitignore` + PreToolUse hook | L1 | Exposing .env secrets causes incidents → must block proactively | `sensitive_protection.gitignore && sensitive_protection.hook_exists` (a hook from any source) |
| C4 | Rules separated — `.claude/rules/` has ≥ 2 files with distinct scopes | L2 | Prevents CLAUDE.md bloat; role-based loading improves context efficiency | `rules.count ≥ 2 && rules.have_distinct_scope` |
| C5 | External system connected — MCP server configured | L2 | Direct access to DB/API → judgment based on facts instead of code | `mcp.configured` |
| C6 | Progressive Disclosure — conditional loading (glob/skill) | L3 | Always loading all rules explodes context; load only when needed | `conditional_load_evidence ≥ 1` |

---

## Axis 3 — Planning · User × Behavioral [1 item]

> "Do you plan first?" — Do you use spec/plan·AskUserQuestion to eliminate ambiguity before saying "go"?

| # | Check Item | L | Why It Matters | Judgment Basis (SESSION_USER, AUTOMATION fallback) |
|---|-----------|:-:|----------------|--------------------------|
| B2 | Plan before execute — use specify/scaffold/plan skills | L2 | The quality gap between "start coding immediately" vs "plan first then execute" is large | `metrics.plan_first_ratio ≥ 0.3 OR AUTOMATION.planning_artifacts.exist` (any kind: `spec`, `partition_manifest`, `design`, `brief`, `insights`; the artifact fallback requires Project scope) |

---

## Axis 4 — Execution · User+Project × Behavioral [3 items]

> "How do you assign work?" — Solo vs delegating to subagents, how is work arranged via team·subagent·orchestration?

| # | Check Item | L | Why It Matters | Judgment Basis (SESSION_USER, SESSION_PROJECT) |
|---|-----------|:-:|----------------|--------------------------|
| B3 | Delegation usage — sessions with Agent calls | L2 | Protects main context + improves both speed and quality through parallelization | `metrics.delegation_ratio ≥ 0.4` (sessions with ≥ 1 `Agent`/`Task` spawn ÷ sessions) |
| B5 | Parallel execution — several subagents spawned in one message | L3 | Running independent tasks sequentially wastes time | `metrics.parallel_count ≥ 1` — assistant messages (distinct `message.id`) carrying ≥ 2 `Agent`/`Task` spawns; `background_flag_count` is information only |
| B6 | Repetitive request automation rate — top-5 tool 3-gram under 30% of total | L3 | Same tool pattern repeated = automation opportunity to extract as skill/hook | `metrics.top_3gram_share < 0.3` (`null` → N/A) |

> This axis is computed for both User global sessions and Project-specific sessions. Report shows **both User and Project values side by side**.

---

## Axis 5 — Verification · Project × Static+Behavioral [7 items]

> "How do you trust the output?" — Use criteria, separated perspectives, and independent verifiers to avoid self-deceiving.

| # | Check Item | L | Why It Matters | Judgment Basis |
|---|-----------|:-:|----------------|----------------|
| B1 | Completion criteria met — a test run or a verification loop before the session ends | L1 | Ending without verification leaves only the illusion of "done" and increases rework cost | SESSION_PROJECT: `metrics.completion_check_ratio ≥ 0.5` — a test command in the last 30% of the session's tool calls, or a skill/command that role-matches `harness-ops:loop`, `harness-ops:qa`, `harness-ops:build-order` or `harness-ops:autopilot` (the built-in `/loop` scheduler never counts) |
| D1 | Test environment — script or test framework | L1 | Without a verification tool, AI output quality cannot be confirmed | AUTOMATION: `test_runner_configured` |
| D2 | Formatter/linter auto-applied — PostToolUse hook | L1 | Manual format instructions every time = repeated cost; one hook solves it | AUTOMATION: `posttool_format_hook` |
| D3 | Dangerous actions blocked — PreToolUse hook exists | L1 | Safety net against mistakes like rm -rf, force push | AUTOMATION: `pretool_block_hook` |
| D4 | Project skills/agents actually used — confirmed called in sessions | L2 | Built but not used has no value; verify actual usage | Phase 2 join: AUTOMATION `skills[].key` ∩ SESSION_PROJECT (`skills_invoked` ∪ `commands_invoked`), or AUTOMATION `agents[].key` ∩ SESSION_PROJECT `agents_invoked`, has ≥ 1 key. N/A when Project scope is off or SESSION_PROJECT is N/A |
| D5 | Creator/verifier AI separated — a separate checker is set up and used | L3 | Same AI implementing and verifying creates confirmation bias; separation stabilizes quality | **Set up** = AUTOMATION `verifier_agents` or `checker_citations` non-empty (check-harness's four analyzers never count). **Used** = SESSION_PROJECT `skills_invoked` ∪ `commands_invoked` role-matches `harness-ops:specify`, `harness-ops:loop`, `harness-ops:coherence-audit`, `harness-ops:crew` or `harness-ops:agent-orchestrate`, or names the built-in `code-review`, or a `verifier_agents` key is in `agents_invoked`. Both → PASS · one → WEAK_PASS · neither → FAIL. When SESSION_PROJECT is N/A, Used is unknown: set up → WEAK_PASS, not set up → N/A. |
| D6 | Unattended runs are bounded — every autopilot ledger sets all six limits | L3 | A run nobody watches must stop itself; an unbounded overnight run can burn time, money and the branch | AUTOMATION `unattended.conforming`: `null` (no real-ledger `autopilot.md`) → N/A · `true` → PASS · `false` → FAIL, naming each `unattended.autopilot_files[].path` and its `missing_limits` (`wall_clock_cap_hours`, `max_ticks`, `consecutive_park_cap`, `per_tick_timeout_seconds`, `crash_loop`, `killswitch_path`) |

---

## Axis 6 — Compounding · User+Project × Growth [4 items]

> "How do you improve?" — Does what's learned in sessions flow back into harness artifacts (SKILL·Docs·CLAUDE.md) and accumulate?

| # | Check Item | L | Why It Matters | Judgment Basis |
|---|-----------|:-:|----------------|----------------|
| E1 | At least one of CLAUDE.md/rules/docs/loop lessons updated recently | L1 | If config is never updated, learning doesn't accumulate | AUTOMATION: `compounding.claude_md_updated_30d OR compounding.rules_added_90d > 0 OR compounding.docs_learnings_exist OR lessons.updated_30d` (a real-ledger `loop.md` committed within 30 days) |
| B4 | Session handoff — ledger/memory write evidence | L2 | Without handoff, next session repeats the same explanations | SESSION_*: `metrics.handoff_ratio ≥ 0.5` among long sessions — a write to `progress.md`, `build_order.md`, `pipeline.md`, `autopilot.md`, `MEMORY.md` or a `/memory/` path, or a session-wrap/wrap/compound/remember/handoff skill |
| E2 | Learning recorded — a learning write or a wrap-type skill ≥ 1 time | L2 | Session learning must be externally recorded to be usable in the next session | Phase 2 join over either session report: `metrics.learning_write_sessions ≥ 1` (a write to `CLAUDE.md`, `loop.md`, `MEMORY.md`, `.claude/rules/`, `/memory/` or `/docs/learnings/`), OR a key in `skills_invoked` ∪ `commands_invoked` whose skill part is session-wrap, wrap, compound, remember or handoff |
| E3 | New skill·hook·agent or hardened lesson added to project in last 90 days | L3 | Improvement must crystallize into an artifact to achieve L3 (self-sustaining) | AUTOMATION: `compounding.skills_added_90d ≥ 1 OR compounding.hooks_added_90d ≥ 1 OR compounding.agents_added_90d ≥ 1 OR lessons.hardened_added_90d ≥ 1` (a lesson promoted to `form: gate1-command` or `gate3-item`) |

---

## Judgment Status

| Status | Meaning |
|--------|---------|
| **PASS** | Evidence-based condition met |
| **WEAK_PASS** | Condition met but quality is low (Quick Win candidate) |
| **FAIL** | No evidence or explicit failure |
| **N/A** | Not applicable to project type, or unable to collect evidence — including a source the item depends on that was missing, had an unexpected shape, whose script failed or whose output is missing or has mismatched `params` (the warning is the evidence) |

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
| **Ghost entry** | A `skillUsage` key that matches no installed skill after name normalisation (`references/skill-aliases.tsv`), and is neither a built-in, renamed history of an installed skill, nor a bare record of one owned skill. |
| **Trigger collision** | 2+ distinct skills reachable by the same trigger: they share a bare skill name (e.g. built-in `loop` and `harness-ops:loop`), or the same `"/xxx"` appears in two descriptions. |
| **Progressive Disclosure** | The "load only when needed" principle. |
| **Plan-first ratio** | Sessions that invoked (by skill or typed slash command) a planning skill — `harness-ops:specify`, `scaffold`, `requirements-interview`, `decompose`, `crew`, `team-design`, or `harness-factory:design` / `team-design` — or entered plan mode, ÷ sessions analyzed. |
| **Handoff** | In a long session, writing state the next session reads — `progress.md`, `build_order.md`, `pipeline.md`, `autopilot.md`, `MEMORY.md` or a `/memory/` file — or running a session-wrap/wrap/compound/remember/handoff skill. |
| **Compounding** | Learning from sessions flowing back into SKILL·rules·docs so the harness grows. |
| **Verifier agent** | A project agent (`agents/` or `.claude/agents/`) whose role, judged from its name and description, is to check work someone else produced. check-harness's four analyzers are excluded. Mitigates confirmation bias. |
| **Unattended run** | A multi-tick autopilot run nobody watches; bounded when its `autopilot.md` `## Config` sets all six limits. |

---

*Total 26 items (6 axes) | L1: 9 items, L2: 10 items, L3: 7 items*
