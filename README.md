# harness-ops

A Claude Code plugin for **Harness Engineering**.

The art of designing environments where AI agents work well — 7 skills covering the full harness lifecycle: diagnose, plan, build, test, and maintain.

## Skills

| Skill | Description | Command |
|-------|-------------|---------|
| **check-harness** | Diagnose harness maturity via 6-axis / 24-item checklist + 2×3 matrix (Static/Behavioral/Growth × User/Project). Runs 4 parallel subagents. | `/harness-ops:check-harness` |
| **scaffold** | Interview-driven greenfield scaffolding — code structure, test infra, guard rails, and CLAUDE.md with domain context | `/harness-ops:scaffold` |
| **specify** | Turn a goal into a structured implementation plan: L0 Goal → L1 Context → L2 Decisions → L3 Requirements → L4 Tasks (spec.md) | `/harness-ops:specify "goal"` |
| **deep-interview** | Socratic requirements interview — clarifies ambiguous goals through structured questioning | `/harness-ops:deep-interview "topic"` |
| **qa** | Systematically QA test any app — auto-selects browser / computer / CLI mode, produces before/after health score and fix report | `/harness-ops:qa [target]` |
| **doc-drift** | Audit all context documents Claude loads (CLAUDE.md, MEMORY.md, skills, agents, plugins) for outdated claims, contradictions, and risky wording | `/harness-ops:doc-drift` |
| **agent-orchestrate** | Analyze a task and execute the optimal orchestration pattern (sequential / parallel / team / ralph-loop) | `/harness-ops:agent-orchestrate "task"` |
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
/harness-ops:deep-interview "I'm not sure what to build"

# Turn a goal into a full implementation plan
/harness-ops:specify "implement user authentication"

# QA test a running app
/harness-ops:qa http://localhost:3000

# Check if your context docs are stale or contradictory
/harness-ops:doc-drift
```

## Usage with Gemini CLI

The repo ships `.gemini/commands/harness-ops/*.toml` files — Gemini CLI reads the `harness-ops/` subdirectory name as the namespace prefix, registering skills as `/harness-ops:skill-name`.

### Quick Start

```
/harness-ops:check-harness
/harness-ops:specify "implement user authentication"
/harness-ops:qa http://localhost:3000
/harness-ops:scaffold
/harness-ops:deep-interview "topic"
/harness-ops:doc-drift
/harness-ops:agent-orchestrate "task"
```

### Installation (global — available in any project)

```bash
# Symlink the harness-ops commands into the Gemini global commands directory
ln -s /path/to/harness-ops/.gemini/commands/harness-ops ~/.gemini/commands/harness-ops
```

After linking, open any Gemini CLI session and type `/harness-ops` to see all 7 skills.

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
  deep-interview.md
  doc-drift.md
  agent-orchestrate.md
  generate-team.md      # Bridge to harness-factory plugin
skills/                 # Skill implementations
  check-harness/SKILL.md
  scaffold/SKILL.md
  specify/SKILL.md
  deep-interview/SKILL.md
  qa/SKILL.md
  doc-drift/SKILL.md
  agent-orchestrate/SKILL.md
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

## License

Internal use only.
