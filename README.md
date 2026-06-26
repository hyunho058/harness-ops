# harness-ops

A Claude Code plugin for **Harness Engineering**.

The art of designing environments where AI agents work well — 11 skills covering the full harness lifecycle: diagnose, plan, build, test, and maintain — now including a **resumable, unattended multi-feature build pipeline** (`loop` → `build-order` → `autopilot`).

## Skills

| Skill | Description | Command |
|-------|-------------|---------|
| **check-harness** | Diagnose harness maturity via 6-axis / 24-item checklist + 2×3 matrix (Static/Behavioral/Growth × User/Project). Runs 4 parallel subagents. | `/harness-ops:check-harness` |
| **scaffold** | Interview-driven greenfield scaffolding — code structure, test infra, guard rails, and CLAUDE.md with domain context | `/harness-ops:scaffold` |
| **specify** | Turn a goal into a structured implementation plan: L0 Goal → L1 Context → L2 Decisions → L3 Requirements → L4 Tasks (spec.md) | `/harness-ops:specify "goal"` |
| **requirements-interview** | Socratic requirements interview — clarifies ambiguous goals through structured questioning | `/harness-ops:requirements-interview "topic"` |
| **qa** | Systematically QA test any app — auto-selects browser / computer / CLI mode, produces before/after health score and fix report | `/harness-ops:qa [target]` |
| **context-audit** | Audit all context documents Claude loads (CLAUDE.md, MEMORY.md, skills, agents, plugins) for outdated claims, contradictions, and risky wording | `/harness-ops:context-audit` |
| **agent-orchestrate** | Analyze a task and execute the optimal orchestration pattern (sequential / parallel / team / ralph-loop) | `/harness-ops:agent-orchestrate "task"` |
| **loop** | Run a task as a supervised verification loop — establishes a 3-gate contract (Pass/Fail · Quantitative · Qualitative), iterates Work→Verify→Fix until gates pass, emits an evidence report, and escalates at autonomy boundaries (schema / migration / auth / payment / spec conflict). **Resumable across compaction**: run-state persists to `progress.md`, so the anti-spin counter and progress survive a compact and a long/unattended run picks up where it left off. **Compounds across runs**: self-learning `## Lessons` (reloaded each run, recorded on failure), maker≠checker Gate 3 (a separate subagent scores the qualitative gate), and an opt-in scheduled heartbeat | `/harness-ops:loop "task"` |
| **build-order** | Orchestrate **many** feature specs through `loop` as one resumable build — generates a topological `build_order.md` ledger, drives each ready feature via `/loop` (verify-first, so already-built features pass without rework), advances on green and **parks-and-continues** independent features on escalation. The durable ledger survives context compaction. | `/harness-ops:build-order [specs glob\|resume]` |
| **autopilot** | Run a `build-order` **unattended** (overnight) — a safety-governor + scheduler (ScheduleWakeup primary + durable cron backstop) that ticks build-order with **six hard limits** (wall-clock · max-tick · consecutive-park · per-tick-timeout · crash-loop · kill-switch) and halts safely. **Never drives a live session** (no tmux / `/compact` injection); resumable across session death. | `/harness-ops:autopilot [start\|status\|stop]` |
| **worktree** | Create / list / remove isolated git worktrees so you can run independent parallel Claude Code sessions on separate branches without interference | `/harness-ops:worktree [create\|list\|remove]` |
| **generate-team** | Design and build an agent team architecture — delegates to the `harness-factory` plugin (must be installed separately) | `/harness-ops:generate-team [description]` |

## Subagents

Four specialized subagents used internally by `check-harness`:

| Agent | Role |
|-------|------|
| `skill-portfolio-analyzer` | Evaluates installed skills coverage and gaps |
| `session-pattern-analyzer` | Analyzes execution patterns from session history |
| `context-quality-reviewer` | Reviews CLAUDE.md and context document quality |
| `project-automation-auditor` | Audits hooks, automations, and workflow integrations |

## Installation

```bash
# 1. Add the harness marketplace (one-time, run from repo root)
claude plugin marketplace add .

# 2. Install the plugin globally
claude plugin install harness-ops@harness-ops-marketplace
```

## Quick Start

```bash
# Diagnose your current project's harness
/harness-ops:check-harness

# Scaffold a new project with AI-optimized structure
/harness-ops:scaffold

# Clarify unclear requirements through structured interview
/harness-ops:requirements-interview "I'm not sure what to build"

# Turn a goal into a full implementation plan
/harness-ops:specify "implement user authentication"

# QA test a running app
/harness-ops:qa http://localhost:3000

# Check if your context docs are stale or contradictory
/harness-ops:context-audit

# Orchestrate many specs into one resumable build (drive each via /loop)
/harness-ops:build-order specs/*/spec.md

# Run that build-order unattended overnight, with safety limits + a kill-switch
/harness-ops:autopilot start ./build_order.md
```

## The Loop: compounding verification

`loop` (and the Ralph-Loop pattern in `agent-orchestrate`) goes beyond a one-shot "fix until green." Three additions make the loop improve over time while keeping the existing 3-gate contract, autonomy fence, and evidence report intact:

- **Self-learning lessons** — when a run escalates or a gate fails, the cause is recorded (with your approval) into a `## Lessons` section of that run's `loop.md`. On the next run of the *same* contract, Phase 0 reloads those lessons and folds them back into the gates — so a past mistake becomes a permanent check. Hardened to a deterministic check (Gate-1 command / Gate-3 item) where possible, else carried as context. Lessons are scoped to their `loop.md` (no cross-contract propagation by design).
- **maker ≠ checker** — the deterministic gates (build / test / metrics) still run inline, but the qualitative Gate 3 is scored by a *separate* checker subagent that never sees the author's reasoning, so a run can't inflate its own score. Falls back to a clearly-flagged `unverified` when no subagent tool is available.
- **Opt-in automation (heartbeat)** — schedule an approved contract to re-run unattended:

  ```
  /loop <interval> /harness-ops:loop <task|spec path> mode: unattended
  ```

  The `mode: unattended` marker is what flips the loop into headless behavior — without it, a self-paced re-run still behaves interactively (you approve lessons, you get asked at the fence). In unattended mode:

  - **Escalation surfacing + fallback** — at the autonomy fence (or when an iteration makes no `fail→pass` progress), the tick stops and notifies you via `PushNotification`. If `PushNotification` isn't available in the environment, the escalation reason is appended to `<specDir>/loop-escalation.md` for you to find next session. Either way the tick stops there — it **never pushes through the fence and never auto-merges** (the merge stays with you, and `block-main-push` is not bypassed).
  - **Unattended lessons** — with no human present to approve, candidate lessons are auto-appended to `## Lessons` tagged `source: auto-unattended` (rather than `human-approved`), so the loop still compounds while running headless. The tag lets you review or prune them in a later interactive session, keeping you the curation owner.

All three are additive and opt-in: a `loop.md` with no `## Lessons` and an invocation with no `mode: unattended` marker behaves exactly as before. The one always-on change is that Gate 3 is now checker-scored when a subagent tool is available.

## The night-loop stack: `loop` → `build-order` → `autopilot`

Three layers compose into a pipeline that can build a multi-feature project **unattended overnight** — throw approved specs at it, sleep, and review in the morning. Each layer keeps its state on disk so the whole run survives the context compactions (and even a session death) a multi-hour run hits.

```
③ autopilot   — schedules ticks + enforces six safety limits (judgment = 0; never drives a live session)
   │ ticks: /build-order resume
②  build-order — many specs → drive each ready feature via /loop; green→done, escalate→park + continue independents
   │ per feature: /loop (verify-first)
①   loop       — one feature to "done" through the 3 gates; resumable across compaction
```

- **① `loop`** is resumable — `progress.md` keeps the run-state (iteration, anti-spin counter, gate results) so a compact can't make it thrash or restart.
- **② `build-order`** is the layer above: it plans a topological `build_order.md`, batch-approves every feature's gate contract up front, then drives each ready feature through `loop`. A feature that escalates is **parked** (sticky until a human un-parks it) while independent features keep going. The gates are the only "done" signal — already-built features verify-green with no rework.
- **③ `autopilot`** keeps `build-order` ticking on a schedule (a `ScheduleWakeup` primary cadence + a durable `CronCreate` backstop that resurrects a hung/dead tick), enforcing six hard limits and a kill-switch file. It is a *governor*: judgment = 0, it never decides the work and — by using a **scheduled fresh-tick model rather than driving a live session** — it never injects keystrokes or `/compact` into a running session.

The three layers nest: `autopilot.md` (which tick) ⊃ `build_order.md` (which feature) ⊃ `loop.md` + `progress.md` (where inside that feature). Everything is opt-in and additive — use `loop` alone for one feature, add `build-order` for many, add `autopilot` to run them unattended.

## Usage with Gemini CLI

The repo ships `.gemini/commands/harness-ops/*.toml` files — Gemini CLI reads the `harness-ops/` subdirectory name as the namespace prefix, registering skills as `/harness-ops:skill-name`.

> **Note:** the Gemini `.toml` files **embed a copy** of each skill's `SKILL.md`, so they must be regenerated when a skill changes. The newest work is **Claude Code first**: `build-order` and `autopilot` have no `.toml` yet, and `loop.toml` does not yet include the latest resumability / pre-approval additions. Gemini CLI therefore exposes the original 9 skills — regenerate the toml files to bring the new capabilities to Gemini.

### Quick Start

```
/harness-ops:check-harness
/harness-ops:specify "implement user authentication"
/harness-ops:qa http://localhost:3000
/harness-ops:scaffold
/harness-ops:requirements-interview "topic"
/harness-ops:context-audit
/harness-ops:agent-orchestrate "task"
/harness-ops:loop "task"
/harness-ops:worktree create feature/new-task
```

### Installation (global — available in any project)

```bash
# Symlink the harness-ops commands into the Gemini global commands directory
ln -s /path/to/harness-ops/.gemini/commands/harness-ops ~/.gemini/commands/harness-ops
```

After linking, open any Gemini CLI session and type `/harness-ops` to see all 9 skills.

### How it works

| | Claude Code | Gemini CLI |
|---|---|---|
| **Install** | `claude plugin install harness-ops` | Symlink `.gemini/commands/harness-ops/` |
| **Invoke** | `/harness-ops:check-harness` | `/harness-ops:check-harness` |
| **Command definitions** | `commands/*.md` | `.gemini/commands/harness-ops/*.toml` |
| **Skill logic** | `skills/{name}/SKILL.md` | same file (embedded in toml) |

---

## Project Structure

```
.claude-plugin/
  marketplace.json      # Marketplace manifest (source: ./plugins/harness-ops)
  plugin.json           # Plugin manifest
commands/               # Slash commands — one .md per skill
  qa.md
  check-harness.md
  scaffold.md
  specify.md
  requirements-interview.md
  context-audit.md
  agent-orchestrate.md
  loop.md
  build-order.md
  autopilot.md
  worktree.md
  generate-team.md      # Bridge to harness-factory plugin
skills/                 # Skill implementations
  check-harness/SKILL.md
  scaffold/SKILL.md
  specify/SKILL.md
  requirements-interview/SKILL.md
  qa/SKILL.md
  context-audit/SKILL.md
  agent-orchestrate/SKILL.md
  loop/SKILL.md
  build-order/SKILL.md
  autopilot/SKILL.md
  worktree/SKILL.md
agents/                 # Subagent definitions
  skill-portfolio-analyzer.md
  session-pattern-analyzer.md
  context-quality-reviewer.md
  project-automation-auditor.md
hooks/
  hooks.json            # Hook registration
plugins/
  harness-ops -> ../    # Symlink for marketplace path resolution
.claude/
  settings.json
.gemini/
  commands/harness-ops/ # Gemini CLI skill definitions (one .toml per skill)
```

## How It Works

Commands in `commands/` delegate to their corresponding `skills/` file:

```
/harness-ops:qa  →  commands/qa.md  →  reads skills/qa/SKILL.md
```

`skills/` files are the single source of truth for all skill logic. Edits to the source repo take effect immediately via the `plugins/harness-ops -> ../` symlink — no reinstall needed for local development. For the globally-installed plugin cache, run `claude plugin update harness-ops` to sync changes.

