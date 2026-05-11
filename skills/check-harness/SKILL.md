---
name: check-harness
argument-hint: ""
description: |
  Harness maturity diagnosis — evaluates the harness cycle (Scaffolding → Context → Planning →
  Execution → Verification → Compounding) using a **6-axis 24-item checklist** and a
  **2×3 analysis matrix** (Static/Behavioral/Growth × User/Project).
  All judgments stem from the gap between "what is set up (Static) ↔ what is actually done (Behavioral)"
  or "whether the harness is growing (Growth)".
  Runs 4 subagents in parallel (skill-portfolio-analyzer, session-pattern-analyzer,
  context-quality-reviewer, project-automation-auditor).
  session-pattern-analyzer is run twice — once for User global scope and once for the current
  project — to separate User/Project scopes.

  Use whenever the user asks to audit their Claude Code harness, review skill
  portfolio health, evaluate execution patterns across sessions, check project
  context/rules quality, or wants to know what's missing in their AI setup —
  even if they don't say "check-harness" explicitly.

  Trigger: "/check-harness", "check harness", "harness check", "harness audit",
  "settings check", "what's missing", "harness diagnosis",
  "maturity check", "my claude setup", "skill cleanup".
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Agent
  - AskUserQuestion
---

# /check-harness — Harness Maturity Diagnosis (v3)

Evaluates along the **6-axis cycle**: **Scaffolding → Context → Planning → Execution → Verification → Compounding**.
Checklist source: `references/checklist.md` (must read first to confirm item definitions).

**Definition of analysis**
> Measure the **gap** between what is set up (Static) and what is actually done (Behavioral), across the User/Project scopes.
> Axis 6 (Compounding) is the only time-axis — it checks whether learning flows back into artifacts and accumulates (Growth).

**2 deliverables**
1. **Scorecard** — PASS/WEAK_PASS/FAIL/N/A per axis + User/Project maturity levels
2. **Action report** — TL;DR + cycle narrative + Quick Wins

**Output format** — Rich per-axis render in conversation + HTML/MD file save + auto-open
- **Conversation**: 6 × per-axis sections + inline ASCII score bars + checklist tables (Phase 3 A block)
- **Files**: saved to `.harness/check-reports/check-harness-{YYYY-MM-DD}-{scope}/`
  - `report.html` — visual report (CSS score gauge, per-axis expandable panels, self-contained)
  - `report.md` — markdown mirror (for diff·git·archive)
- **Auto-open**: run `Bash: open {dir}/report.html` at the end
- End of report one-liner: `📁 Saved: {dir}/ · 🌐 Opened: report.html`

---

## Phase 0 — Scope Decision

If scope is explicit in user input, use it as-is:
- `overall` / `user` → User only
- `project` → Project only
- `all` / unspecified → **Both**

If scope is ambiguous, use `AskUserQuestion`:

```
question: "How far should we diagnose?"
options:
  - Both (User + Project) — Full diagnosis (Recommended)
  - User only (global · skill cleanup + all session habits)
  - Project only (current project context·automation·project sessions)
```

### Project root discovery (when Project scope is included)

Walk up from cwd and find the directory containing `.claude` or `CLAUDE.md` as `PROJECT_ROOT`. If not found, deactivate Project scope.

### Cache directory

```bash
mkdir -p /tmp/cc-cache/check-harness/
```

Output paths:
- `/tmp/cc-cache/check-harness/PORTFOLIO.json`
- `/tmp/cc-cache/check-harness/SESSION_USER.json`
- `/tmp/cc-cache/check-harness/SESSION_PROJECT.json`
- `/tmp/cc-cache/check-harness/CONTEXT.json`
- `/tmp/cc-cache/check-harness/AUTOMATION.json`

---

## Phase 1 — Parallel Data Collection

**Spawn all subagents for the selected scope in a single message.**

### User scope agents (2)

```
Agent(
  subagent_type: "skill-portfolio-analyzer",
  description: "Skill portfolio health scan",
  prompt: """
    Cross-analyze all installed skills/plugins/MCP against ~/.claude.json.
    Include enabledPlugins (user/project), mcpServers (user + project .mcp.json),
    installed plugin inventory, MCP call usage (last 30 days).
    Include current_state/unused_mcp/plugin_findings fields.
    Save to /tmp/cc-cache/check-harness/PORTFOLIO.json.
    project_root={PROJECT_ROOT if available}
    dead_days=90, low_value_days=60, low_value_count=3
  """
)

Agent(
  subagent_type: "session-pattern-analyzer",
  description: "User-wide session pattern scan",
  prompt: """
    scope=overall, days=7, long_session_min=20.
    Analyze tool_use metadata only from all sessions under ~/.claude/projects/. Never read prompt text.
    Save to /tmp/cc-cache/check-harness/SESSION_USER.json.
  """
)
```

### Project scope agents (3)

```
Agent(
  subagent_type: "session-pattern-analyzer",
  description: "Project-scope session pattern scan",
  prompt: """
    scope=current_project, project_dir={PROJECT_ROOT}, days=30, long_session_min=20.
    Target only sessions for this project. tool_use metadata only.
    Save to /tmp/cc-cache/check-harness/SESSION_PROJECT.json.
  """
)

Agent(
  subagent_type: "context-quality-reviewer",
  description: "Project context quality review",
  prompt: """
    project_root={PROJECT_ROOT}
    Evaluate CLAUDE.md + .claude/rules/* + .gitignore + settings.json + MCP config.
    Save to /tmp/cc-cache/check-harness/CONTEXT.json.
  """
)

Agent(
  subagent_type: "project-automation-auditor",
  description: "Project automation, verification & compounding audit",
  prompt: """
    project_root={PROJECT_ROOT}
    session_report=/tmp/cc-cache/check-harness/SESSION_PROJECT.json  (reference if available)
    Audit test/hooks/verifier/isolation + collect **compounding signals** (git-log-based recent changes to CLAUDE.md·rules·docs·skills·hooks).
    Save to /tmp/cc-cache/check-harness/AUTOMATION.json.
  """
)
```

**For Both scope, spawn all 5 in a single message** (project-session and automation-auditor have a dependency, but auditor is designed to run without session — parallel OK).

After completion, read the JSONs and hold `PORTFOLIO`, `SESSION_USER`, `SESSION_PROJECT`, `CONTEXT`, `AUTOMATION` in memory.

---

## Phase 2 — Checklist Judgment (6-axis mapping)

For each of the 24 items, determine PASS/WEAK_PASS/FAIL/N/A and record an evidence string.

### Per-axis data source mapping

| Axis | Source | Scope | Judgment fields |
|------|--------|-------|-----------------|
| **1. Scaffolding** | PORTFOLIO | User | summary (A1–A5) |
| **2. Context** | CONTEXT | Project | claude_md·rules·sensitive (C1–C6) |
| **3. Planning** | SESSION_USER + AUTOMATION (fallback) | User | plan_first_ratio (B2) OR planning_artifacts_exist |
| **4. Execution** | SESSION_USER + SESSION_PROJECT | User+Project | delegation/parallel/top_ngram (B3·B5·B6) — **computed for each scope separately** |
| **5. Verification** | SESSION_PROJECT + AUTOMATION | Project | completion_check + D1–D5 |
| **6. Compounding** | AUTOMATION.compounding + SESSION (wrap/memory) | Both | E1·B4·E2·E3 |

### Axis 4 (Execution) note

B3/B5/B6 record **both User and Project values**. Axis-level judgment follows this rule:
- Both scope: use the **lower** of User/Project for axis judgment (weakest link principle)
- Single scope: use only that scope's value

### Status rules

- **PASS** — evidence clearly met
- **WEAK_PASS** — condition met but `weak_pass_flags` field present in report
- **FAIL** — no evidence or explicit failure
- **N/A** — no data available (e.g., 0 sessions) or not applicable to project type

### Maturity calculation

**Per-axis level**
- All L1 items PASS/WEAK_PASS → L1 achieved
- All L2 items also PASS → L2, L3 also → L3

**User Maturity** = min(axis 1, axis 3, axis 4-User portion, axis 6-User portion)
**Project Maturity** = min(axis 2, axis 4-Project portion, axis 5, axis 6-Project portion)

**Score (per axis, 0–100)**
- Item score: PASS=1, WEAK_PASS=0.5, FAIL=0, N/A=excluded
- Weights: L1×3, L2×2, L3×1
- Axis score = Σ(score × weight) / Σ(weight) × 100

**Harness Score**
- User Score = mean(axis 1, axis 3, axis 4-User)
- Project Score = mean(axis 2, axis 4-Project, axis 5)
- Compounding (axis 6) is reported as an **independent axis score** rather than being added to User/Project (accumulation is a time axis — point-in-time aggregation would distort)
- **Harness Score** = (User + Project + Compounding) / 3 (when Both scope)
- Grade: 90+ Excellent / 75+ Good / 60+ Fair / <60 Needs Work

**Progress to next level**: `passing items at current level / items required for next level`

---

## Phase 2.5 — TL;DR & Action Synthesis

Using Phase 2 judgments as input, generate the key summary for the top of the report first.

### 5 variables to generate

1. **`headline`** (1 sentence) — User/Project maturity + "biggest problem" + "easiest starting point"
   e.g.: *"User L2 / Project L1 — CLAUDE.md is missing run commands and the compounding axis is thin. Start by adding 3 lines of dev commands."*

2. **`cycle_line`** (6 items, 1 line each) — per-axis one-liner in cycle order:
   - `1. Scaffolding — {one line}`
   - `2. Context — {one line}`
   - `3. Planning — {one line}`
   - `4. Execution — {one line, may include User/Project comparison}`
   - `5. Verification — {one line}`
   - `6. Compounding — {one line}`

3. **`strength`** (1 sentence) — strength drawn from axes with few FAILs and many PASSes.

4. **`weakness`** (1 sentence) — weakness from axes with concentrated FAILs.

5. **`actions`** (3–7 items) — 3-tier classification:
   - 🟢 **Quick Wins**: single command / one-line change
   - 🟡 **Worth Organizing**: edit one file
   - 🔴 **Long-term Improvements**: structural changes

### Selection rules

- High Priority Finding → must be included
- Prioritize items with a clear command/file path
- Remove duplicates
- Maximum 7 items
- **Include at least 1 suggestion based on Runtime inventory (PORTFOLIO)**
- **Include at least 1 suggestion when Compounding (axis 6) FAILS** — e.g., "add what you learned this session to rules/"

### Action tone enforcement

- ❌ "X is missing" / "X is insufficient" / "You must do X"
- ✅ "Adding X will {effect}" / "Doing X makes things easier"
- Each action includes an `Expected effect:` field

---

## Phase 3 — Report Generation (3 deliverables)

**Top-heavy + cycle narrative + per-axis detail**: fast at the top, progressively richer per axis below.

**Generate all 3 deliverables simultaneously**:
- **A. Conversation render** (markdown template below) — output immediately
- **B. report.md** (same content as A) — Write
- **C. report.html** (based on references/html-template.html, self-contained) — Write, then `open`

### A/B Markdown template (shared for conversation + report.md)

```markdown
# 🧭 Harness Maturity Report

**{YYYY-MM-DD}** · Scope: `{user|project|all}` · Project: `{name or "-"}`

---

## 🧭 Harness Score: **{NN} / 100**  ({Excellent|Good|Fair|Needs Work})

```
👤 User Scope    L{n}  ▓▓▓▓▓▓▓░░░  {XX}% → L{n+1}   (Score: {NN})
📁 Project Scope L{n}  ▓▓▓▓▓▓▓▓░░  {XX}% → L{n+1}   (Score: {NN})
🔁 Compounding   L{n}  ▓▓▓▓░░░░░░  {XX}% → L{n+1}   (Score: {NN})
```

> User = `~/.claude/` global (Scaffolding·Planning·Execution-User axes)
> Project = this project (Context·Verification·Execution-Project axes)
> Compounding = whether the harness is growing (axis 6, shared)

## 🎯 Summary

> {headline}

**Strengths**: {strength}
**Areas to Improve**: {weakness}

---

## 🔄 Cycle Overview

> One line per axis in Scaffolding → Context → Planning → Execution → Verification → Compounding order.

1. **Scaffolding** · 👤 User — {cycle_line[0]}
2. **Context** · 📁 Project — {cycle_line[1]}
3. **Planning** · 👤 User — {cycle_line[2]}
4. **Execution** · 👤+📁 — {cycle_line[3]}
5. **Verification** · 📁 Project — {cycle_line[4]}
6. **Compounding** · 👤+📁 — {cycle_line[5]}

---

## ✅ Recommended Actions

> Pick any that feel manageable. Each action shows **scope (👤/📁)**.

### 🟢 Quick Wins
- [ ] {👤|📁} **{action}** — Expected effect: {benefit}
  - Command: `{copy-paste command}`
  - Evidence: {evidence}

### 🟡 Worth Organizing
- [ ] {👤|📁} **{action}** — Expected effect: {benefit}
  - Reference: {file path}
  - Evidence: {evidence}

### 🔴 Long-term Improvements
- [ ] {👤|📁} **{action}** — Expected effect: {benefit}
  - Evidence: {evidence}

---

## 📊 Scorecard (6 Axes)

| Axis | Scope | Score | Level | To next level |
|------|-------|------:|:-----:|:-------------|
| 1. Scaffolding      | 👤 User     | {NN} | L{n} | {XX}% → L{n+1} |
| 2. Context          | 📁 Project  | {NN} | L{n} | {XX}% → L{n+1} |
| 3. Planning         | 👤 User     | {NN} | L{n} | {XX}% → L{n+1} |
| 4. Execution        | 👤+📁        | {NN} | L{n} | {XX}% → L{n+1} |
| 5. Verification     | 📁 Project  | {NN} | L{n} | {XX}% → L{n+1} |
| 6. Compounding      | 👤+📁        | {NN} | L{n} | {XX}% → L{n+1} |

Sessions analyzed: User {Nu} / Project {Np} ({period}) · Scanned: {YYYY-MM-DD HH:MM}

---

## 🔌 Active Runtime State (Runtime Inventory)

> What is **actually accessible** in this Claude Code session right now.

**📦 Plugins** ({enabled_project}/{installed} enabled in this project)
| Plugin | Version | Scope | Skills | Usage last 30d |
|--------|:-------:|:-----:|------:|:--------------|
| ... | ... | 👤📁 | ... | ... |

**🔗 MCP Servers** ({total} total · {unused} unused)
| Server | Scope | Type | Recent calls |
|--------|:-----:|:----:|:--------:|
| ... | ... | ... | ... |

**🧩 Skill origins**
- User standalone: {N}
- Via plugin: {N}
- Project local: {N}

---

<details>
<summary>🧭 2×3 Analysis Matrix (Static/Behavioral/Growth × User/Project)</summary>

|  | Static (set up) | Behavioral (doing) | Growth (accumulating) |
|---|---|---|---|
| 👤 User    | Axis 1 (Score {NN}) | Axis 3 · Axis 4-User (Score {NN}/{NN}) | Axis 6-User (Score {NN}) |
| 📁 Project | Axis 2 (Score {NN}) | Axis 4-Project · Axis 5 (Score {NN}/{NN}) | Axis 6-Project (Score {NN}) |

**Gap summary from cross-analysis**
- Static vs Behavioral (User): {N skills installed but unused → B2 plan-first ratio low}
- Static vs Behavioral (Project): {hook exists but 0 calls / hook needed but absent}
- Growth: {N artifact updates in last 30 days → accumulation status}

</details>

<details>
<summary>📋 Full Checklist (6 axes · 24 items)</summary>

### Axis 1 — Scaffolding (👤 User × Static)
| ID | L | Item | Status | Evidence |
|----|---|------|--------|----------|
| A1 | L1 | 70%+ skills used last 30d | PASS | ... |
| ... |

### Axis 2 — Context (📁 Project × Static)
...

### Axis 3 — Planning (👤 User × Behavioral)

> **B2 judgment rule** (OR condition):
> 1. `SESSION_USER.metrics.plan_first_ratio ≥ 0.3` → PASS, evidence: `"plan_first_ratio: X.XX"`
> 2. `AUTOMATION.planning_artifacts_exist == true` → PASS, evidence: `"planning artifacts found: specs/ (N files)"` — count from AUTOMATION
> 3. AUTOMATION absent (User-scope-only run) → evaluate (1) only, no error
> 4. Both false → FAIL

...

### Axis 4 — Execution (👤+📁 × Behavioral)
> Show both User and Project values

| ID | L | Item | User | Project | Status(min) | Evidence |
|----|---|------|------|---------|-------------|----------|
| B3 | L2 | delegation_ratio ≥ 0.4 | 0.55 | 0.20 | FAIL(project) | ... |
| ... |

### Axis 5 — Verification (📁 Project)
...

### Axis 6 — Compounding (👤+📁 × Growth)
| ID | L | Item | Status | Evidence |
|----|---|------|--------|----------|
| E1 | L1 | CLAUDE.md/rules/docs updated in last 30d | PASS | CLAUDE.md updated 2026-04-02 |
| B4 | L2 | session-wrap/handoff ratio | WEAK_PASS | 0.42 |
| E2 | L2 | wrap/compound/memory calls ≥1 | PASS | session-wrap: 3 calls |
| E3 | L3 | new skill/hook/rule in last 90d | FAIL | 0 items |

</details>

<details>
<summary>🔍 Full Findings List</summary>

**High Priority**
- 💡 {...}

**Medium Priority**
- 💡 {...}

**Low Priority**
- 💡 {...}

</details>

<details>
<summary>🧩 Skill Portfolio Detail (👤 User × Static)</summary>

Total installed skills: {N} · Used last 30d: {X} ({%})

| Category | Count | Description | Examples |
|----------|------:|-------------|---------|
| 😴 Long unused (90d+) | N | ... | ... |
| 👻 Ghost entries only | N | ... | ... |
| 🔁 Duplicate purpose clusters | N | ... | ... |
| 🏷️ Namespace duplicates | N | ... | ... |
| ⚠️ Trigger collisions | N | ... | ... |

</details>

<details>
<summary>⚡ Execution Detail (Recent session habits — User vs Project)</summary>

|                          | 👤 User | 📁 Project |
|--------------------------|-------:|-----------:|
| plan-first ratio         | {X}%   | {X}%       |
| delegation ratio         | {X}%   | {X}%       |
| parallel calls           | {N}    | {N}        |
| handoff ratio            | {X}%   | {X}%       |
| completion check ratio   | {X}%   | {X}%       |
| top 3-gram share         | {X}%   | {X}%       |

**Automation candidates (repeated patterns)**
- User: `Read → Edit → Bash(npm test)` — {N} times
- Project: `...` — {N} times

</details>

<details>
<summary>🔁 Compounding Detail (Axis 6 — harness accumulation)</summary>

- CLAUDE.md updated in last 30d: {Yes/No} ({commit evidence})
- `.claude/rules/` additions in last 90d: {N}
- `skills/` additions in last 90d: {N}
- `hooks/` changes in last 90d: {N}
- `docs/learnings/` exists: {Yes/No}
- session-wrap/compound invocations in sessions: User {N} / Project {N}

**Observations**
- {e.g., no new rules added to this project recently → learning exists only in the human's head}

</details>

📁 Saved: {dir}/ · 🌐 Opened: report.html
```

### Conversation render expansion rules (A block)

When outputting to the conversation, render each axis section with more detail. Per axis:

```
### {N}. {Axis name} · {Scope emoji} · {Status summary}
Score: {NN}/100  L{n}  ▓▓▓▓▓▓▓░░░ {XX}% → L{n+1}

Key findings:
- ✅ {1–2 things going well, with supporting numbers}
- ⚠️ {1–2 improvement points, with supporting numbers}

Checklist:
| ID | L | Item | Status | Evidence |
|----|---|------|--------|----------|
| {row} |

Cheapest next move: {quick win + command or path}
```

Same structure for all 6 axes. Each axis section should be 5–12 lines.

### C block — HTML report generation

1. Read `references/html-template.html` (self-contained HTML — inline CSS, score gauge, per-axis cards, collapsible panels)
2. Replace the following placeholders:
   - `{{GENERATED_AT}}`, `{{SCOPE}}`, `{{PROJECT_NAME}}`
   - `{{HARNESS_SCORE}}`, `{{HARNESS_GRADE}}`
   - `{{USER_SCORE}}`, `{{USER_LEVEL}}`, `{{PROJECT_SCORE}}`, `{{PROJECT_LEVEL}}`, `{{COMPOUNDING_SCORE}}`, `{{COMPOUNDING_LEVEL}}`
   - `{{HEADLINE}}`, `{{STRENGTH}}`, `{{WEAKNESS}}`
   - `{{CYCLE_ROWS}}` — 6 axis one-liners as `<li>{cycle_line}</li>`
   - `{{ACTIONS_GREEN}}`, `{{ACTIONS_YELLOW}}`, `{{ACTIONS_RED}}` — action cards as `<li>`
   - `{{AXIS_CARDS}}` — 6 axis cards (per-axis structure below)
   - `{{INVENTORY_TABLE}}` — runtime inventory table
   - `{{MATRIX_TABLE}}` — 2×3 matrix
   - `{{FINDINGS_LIST}}`
3. Write, then run `Bash: open {dir}/report.html` — opens in the default macOS browser.

Per-axis card block example (repeated inside HTML):
```html
<article class="axis" data-status="{pass|weak|fail|na}">
  <header>
    <h3>{icon} Axis {N} — {name}</h3>
    <div class="score">
      <span class="score-num">{NN}</span>
      <div class="bar"><span style="width:{XX}%"></span></div>
      <span class="level">L{n}</span>
    </div>
  </header>
  <p class="headline">{one-line summary}</p>
  <details><summary>Checklist · {PASS_N}/{TOTAL_N} passed</summary>
    <table>...</table>
  </details>
  <p class="next-move">💡 {quick win}</p>
</article>
```

### Report tone guide

- **No verdict sentences** — "X is missing" ❌
- **Use suggestion sentences** — "Adding X will {effect}" ✅
- Findings labels are unified as **💡 emoji + one suggestion sentence**
- Each action in "Recommended Actions" must include a **copy-pasteable command** or **file path**
- Each line in "Cycle Overview" must include **status (✅/⚠️/❌) + one supporting number**

---

## Hard Rules

1. **Do not read prompt content** — session-pattern-analyzer uses tool_use metadata only
2. **Do not modify project files** — only write reports to `.harness/check-reports/`
3. **Evidence-based evaluation** — every status must include an evidence string
4. **Context awareness** — mark N/A for items not applicable to the project type
5. **Parallel execution** — Phase 1 subagents must be spawned in the same message (5 at once for Both scope)
6. **Separate User/Project sessions** — call session-pattern-analyzer separately per scope (SESSION_USER, SESSION_PROJECT)
7. **Axis 6 (Compounding) is a Growth axis** — report as an independent score, not summed with User/Project (time derivative, not a point-in-time aggregate)
8. **Cache reuse** — the 5 JSON files under `/tmp/cc-cache/check-harness/` can be reused in follow-up analysis
