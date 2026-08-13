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

> **Runtime contract — read this first.** Before executing any step below, read
> `../../references/runtime-tools.md`. This skill names **capabilities**, not runtime tool
> names. The four analyzers are spawned with the pinned `capability:spawn-named-checker`
> procedure — a divergent procedure, so its result must be confirmed by BOTH the named report
> artifact and the subagent registry. A report that exists proves nothing on its own: an agent
> that skipped delegation and wrote it in-context produces an identical file.

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
- **Auto-open**: `capability:run-command` → `open {dir}/report.html` at the end
- End of report one-liner: `📁 Saved: {dir}/ · 🌐 Opened: report.html`

---

## Phase 0 — Scope Decision

If scope is explicit in user input, use it as-is:
- `overall` / `user` → User only
- `project` → Project only
- `all` / unspecified → **Both**

If scope is ambiguous, ask with `capability:ask-user`:

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
capability:spawn-named-checker
  checker: "skill-portfolio-analyzer",
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

capability:spawn-named-checker
  checker: "session-pattern-analyzer",
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
capability:spawn-named-checker
  checker: "session-pattern-analyzer",
  description: "Project-scope session pattern scan",
  prompt: """
    scope=current_project, project_dir={PROJECT_ROOT}, days=30, long_session_min=20.
    Target only sessions for this project. tool_use metadata only.
    Save to /tmp/cc-cache/check-harness/SESSION_PROJECT.json.
  """
)

capability:spawn-named-checker
  checker: "context-quality-reviewer",
  description: "Project context quality review",
  prompt: """
    project_root={PROJECT_ROOT}
    Evaluate CLAUDE.md + .claude/rules/* + .gitignore + settings.json + MCP config.
    Save to /tmp/cc-cache/check-harness/CONTEXT.json.
  """
)

capability:spawn-named-checker
  checker: "project-automation-auditor",
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

### Delegation assertion — required before Phase 2 (divergent-procedure rule)

`capability:spawn-named-checker` is a **divergent** procedure: the two runtimes reach it by
genuinely different means, so parity cannot be guaranteed by running identical bytes. Assert
**both** of the following before using any result:

1. **Artifact** — each expected JSON exists at its `/tmp/cc-cache/check-harness/` path.
2. **Registry** — each analyzer appears as actually defined *and* invoked. Under Antigravity,
   query `manage_subagents`; under Claude Code the spawn is native and its own return is the
   evidence.

Artifact existence alone is **not** sufficient. An agent that skipped delegation and wrote a
well-formed `SESSION_REPORT` from its own context produces a file indistinguishable from the
delegated one — and that is exactly the in-context degradation this skill's maker ≠ checker
separation exists to prevent. Only the registry check tells them apart.

If either assertion fails, **halt and say which** — `unavailable:`, `denied:`, or `unresolved:`
per the map's Halting table. Do not proceed with a partial set of reports; a maturity score
computed from four of five analyzers, presented as a score, misrepresents itself.

After both assertions pass, read the JSONs and hold `PORTFOLIO`, `SESSION_USER`, `SESSION_PROJECT`, `CONTEXT`, `AUTOMATION` in memory.

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

The template (`references/html-template.html`) is a self-contained dark dashboard: top bar → **SVG ring hero** (ring + 6 cycle nodes) → cycle strip → 6 axis cards → recommended next moves → runtime inventory + 2×3 matrix → 3-column findings → footer. It loads Space Grotesk + IBM Plex Mono from Google Fonts with a system-font fallback, and defines status colors as CSS vars (`--green` `oklch(0.78 0.12 155)`, `--amber` `oklch(0.82 0.12 82)`, `--coral` `oklch(0.70 0.15 22)`, `--accent` `oklch(0.74 0.12 262)`, `--na` `#6b7280`) plus the four grade-pill classes.

1. Read `references/html-template.html`.
2. Replace **every** placeholder below (the template and this list must stay in 1:1 parity — no orphan tokens, and a finished render must contain no literal `{{`):

   **Scalars**
   - `{{GENERATED_AT}}`, `{{SCOPE}}`, `{{PROJECT_NAME}}`
   - `{{HARNESS_SCORE}}` (plain integer 0–100, no `%`), `{{HARNESS_GRADE}}` (text: `Excellent|Good|Fair|Needs Work`)
   - `{{HEADLINE}}`, `{{STRENGTH}}`, `{{WEAKNESS}}`
   - `{{USER_SCORE}}`, `{{USER_LEVEL}}`, `{{PROJECT_SCORE}}`, `{{PROJECT_LEVEL}}`, `{{COMPOUNDING_SCORE}}`, `{{COMPOUNDING_LEVEL}}` (scores are plain integers; they also drive mini-bar widths via `width:{{…}}%`)
   - `{{SESSION_ID}}`

   **Ring + grade (computed — see below)**
   - `{{RING_DASHARRAY}}` — the two-value SVG dash for the progress arc
   - `{{GRADE_CLASS}}` — one of `grade-excellent | grade-good | grade-fair | grade-needs-work`
   - `{{NODE1_COLOR}}`, `{{NODE2_COLOR}}`, `{{NODE3_COLOR}}`, `{{NODE4_COLOR}}`, `{{NODE5_COLOR}}`, `{{NODE6_COLOR}}` — the 6 cycle-node fill colors

   **Generated blocks (emit inner HTML; on an empty list emit a single `None` item — never leave the slot blank or tokenized)**
   - `{{CYCLE_STRIP}}` — 6 stage cards (cycle-card markup below)
   - `{{AXIS_CARDS}}` — 6 axis `<article>` cards (axis-card markup below)
   - `{{ACTIONS_GREEN}}`, `{{ACTIONS_YELLOW}}`, `{{ACTIONS_RED}}` — `<li>` action items (action-item markup below)
   - `{{INVENTORY_TABLE}}`, `{{MATRIX_TABLE}}` — runtime inventory blocks / 2×3 matrix grid
   - `{{FINDINGS_HIGH}}`, `{{FINDINGS_MEDIUM}}`, `{{FINDINGS_LOW}}` — `<li>` finding items (finding-item markup below)
3. Write, then `capability:run-command` → `open {dir}/report.html` — opens in the default browser.

#### Ring, node, and grade computation

- **`{{RING_DASHARRAY}}`** = `"{filled} 880"` where `filled = round(HARNESS_SCORE / 100 * 880)` (the ring is `r=140`, circumference ≈ 879.6). Two values are required — a single value would tile the dash instead of drawing one progress arc. Example: score 68 → `"598 880"`.
- **`{{NODE1_COLOR}}` … `{{NODE6_COLOR}}`** map **node N → axis N in cycle order** (1=Scaffolding, 2=Context, 3=Planning, 4=Execution, 5=Verification, 6=Compounding). Each value is that axis's rolled-up **status color**: PASS→`oklch(0.78 0.12 155)`, WEAK→`oklch(0.82 0.12 82)`, FAIL→`oklch(0.70 0.15 22)`, N/A→`#6b7280` (same palette as the axis-card border-left, matching the template's `--green/--amber/--coral/--na`).
- **`{{GRADE_CLASS}}`** from the score bucket: `≥90 → grade-excellent`, `≥75 → grade-good`, `≥60 → grade-fair`, `<60 → grade-needs-work`. `{{HARNESS_GRADE}}` carries the matching visible text.

#### Status → color reference (used by all emitted blocks)

| Status | Accent color | Badge bg | Badge text |
|--------|--------------|----------|------------|
| PASS | `oklch(0.78 0.12 155)` | `rgba(95,207,154,0.16)` | green |
| WEAK | `oklch(0.82 0.12 82)` | `rgba(221,192,102,0.16)` | amber |
| FAIL | `oklch(0.70 0.15 22)` | `rgba(232,122,130,0.16)` | coral |
| N/A | `#6b7280` | `rgba(107,114,128,0.16)` | `#6b7280` |

#### Cycle stage card (×6, into `{{CYCLE_STRIP}}`) — `border-top` = axis status accent color

```html
<div style="background:#1a1e28;border:1px solid #272c38;border-top:2px solid {accent};border-radius:10px;padding:13px 13px 14px;">
  <div style="display:flex;align-items:center;gap:7px;margin-bottom:8px;"><span style="font:600 11px/1 var(--font-mono);color:#8a93a6;">0{N}</span><span style="font:600 13px/1 var(--font-display);">{Axis name}</span></div>
  <div style="font-size:11.5px;line-height:1.45;color:#aab2c2;">{✅|⚠️|❌} {one-liner + one supporting number}</div>
</div>
```

#### Axis card (×6, into `{{AXIS_CARDS}}`) — `border-left` + score bar + node share the axis accent color

```html
<article style="background:#13161e;border:1px solid #272c38;border-left:3px solid {accent};border-radius:14px;padding:17px 18px;display:flex;flex-direction:column;gap:11px;">
  <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;">
    <div>
      <div style="display:flex;align-items:center;gap:8px;"><span style="font:600 11px/1 var(--font-mono);color:#8a93a6;">0{N}</span><h3 style="margin:0;font:600 15px/1.1 var(--font-display);">{name}</h3></div>
      <div style="font:500 11px/1 var(--font-mono);color:#8a93a6;margin-top:5px;">{scope label, e.g. 👤 User · Static}</div>
    </div>
    <div style="text-align:right;min-width:84px;">
      <div style="display:flex;align-items:baseline;justify-content:flex-end;gap:6px;"><span style="font:700 21px/1 var(--font-display);letter-spacing:-0.02em;">{score}</span><span style="font:500 11px/1 var(--font-mono);color:#8a93a6;">L{n}</span></div>
      <div style="height:5px;width:84px;background:#272c38;border-radius:3px;overflow:hidden;margin-top:7px;"><span style="display:block;height:100%;width:{score}%;background:{accent};border-radius:3px;"></span></div>
    </div>
  </div>
  <p style="margin:0;font-size:13px;line-height:1.5;color:#cfd5e2;text-wrap:pretty;">{headline}</p>
  <details style="background:#0f1218;border:1px solid #232834;border-radius:9px;padding:9px 12px;">
    <summary style="font:500 12px/1 var(--font-mono);color:#8a93a6;display:flex;align-items:center;justify-content:space-between;">Checklist <span style="color:#6b7280;">{e.g. 3 pass · 2 weak}</span></summary>
    <table style="width:100%;border-collapse:collapse;margin-top:10px;">
      <!-- one <tr> per checklist row: -->
      <tr style="border-top:1px solid #1f2430;">
        <td style="padding:6px 7px 6px 0;vertical-align:top;font:500 11px/1.3 var(--font-mono);color:#6b7280;white-space:nowrap;">{id}<br /><span style="color:#4d5564;">{L1|L2|L3}</span></td>
        <td style="padding:6px 7px;vertical-align:top;font-size:12px;line-height:1.35;">{item}<div style="color:#8a93a6;font:400 11px/1.35 var(--font-mono);margin-top:2px;">{evidence}</div></td>
        <td style="padding:6px 0 6px 7px;vertical-align:top;text-align:right;white-space:nowrap;"><span style="display:inline-block;padding:2px 8px;border-radius:11px;font:600 10px/1.4 var(--font-mono);background:{badgeBg};color:{badgeColor};">{PASS|WEAK|FAIL|N/A}</span></td>
      </tr>
    </table>
  </details>
  <div style="display:flex;align-items:flex-start;gap:7px;font-size:12.5px;line-height:1.45;color:var(--accent);"><span style="flex-shrink:0;">→</span><span style="text-wrap:pretty;">{next move}</span></div>
</article>
```

#### Action item (`<li>`, into `{{ACTIONS_GREEN/YELLOW/RED}}`) — lead with scope emoji; `<code>` is optional

```html
<li style="background:#13161e;border:1px solid #272c38;border-radius:9px;padding:11px 12px;">
  <div style="font-size:13px;font-weight:600;line-height:1.4;">{👤|📁|👤📁} {action title}</div>
  <div style="font-size:11.5px;color:#8a93a6;line-height:1.45;margin-top:4px;">{expected effect}</div>
  <code style="display:inline-block;margin-top:8px;font:500 11px/1.4 var(--font-mono);background:#0f1218;border:1px solid #232834;padding:3px 7px;border-radius:5px;color:#cfd5e2;">{command or path}</code>
</li>
```

#### Finding item (`<li>`, into `{{FINDINGS_HIGH/MEDIUM/LOW}}`) — bullet color = coral / amber / muted by priority

```html
<li style="font-size:12.5px;line-height:1.5;color:#cfd5e2;padding-left:16px;position:relative;text-wrap:pretty;"><span style="position:absolute;left:0;color:{coral|amber|#8a93a6};">💡</span>{one suggestion sentence}</li>
```

#### Inventory + matrix

- **`{{INVENTORY_TABLE}}`** — emit the Plugins table (name · scope · skills · 30d use), the MCP-servers block, and the Skill-origins counters (user standalone / via plugin / project local), inline-styled to match the surrounding panels. Empty section → a single `None configured` line.
- **`{{MATRIX_TABLE}}`** — emit the 2×3 grid: rows 👤 User / 📁 Project × columns Static / Behavioral / Growth (Growth cell spans both rows), each cell showing the axis label + score, plus the "Gap read" summary line.

**Empty-list rule (all generated blocks):** if a list (actions, findings, inventory rows) has zero items, emit a single muted `None` item — never leave a placeholder unreplaced.

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
