# harness

A Claude Code plugin for **Harness Engineering**.

The art of designing environments where AI agents work well — 7 skills covering the full harness lifecycle: diagnose, plan, build, test, and maintain.

## Skills

| Skill | Description | Command |
|-------|-------------|---------|
| **check-harness** | Diagnose harness maturity via 6-axis / 24-item checklist + 2×3 matrix (Static/Behavioral/Growth × User/Project). Runs 4 parallel subagents. | `/harness:check-harness` |
| **scaffold** | Interview-driven greenfield scaffolding — code structure, test infra, guard rails, and CLAUDE.md with domain context | `/harness:scaffold` |
| **specify** | Turn a goal into a structured implementation plan: L0 Goal → L1 Context → L2 Decisions → L3 Requirements → L4 Tasks (spec.md) | `/harness:specify "goal"` |
| **deep-interview** | Socratic requirements interview — clarifies ambiguous goals through structured questioning | `/harness:deep-interview "topic"` |
| **qa** | Systematically QA test any app — auto-selects browser / computer / CLI mode, produces before/after health score and fix report | `/harness:qa [target]` |
| **doc-drift** | Audit all context documents Claude loads (CLAUDE.md, MEMORY.md, skills, agents, plugins) for outdated claims, contradictions, and risky wording | `/harness:doc-drift` |
| **agent-orchestrate** | Analyze a task and execute the optimal orchestration pattern (sequential / parallel / team / ralph-loop) | `/harness:agent-orchestrate "task"` |

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
# 1. Add the harness marketplace (one-time)
claude plugin marketplace add . --name harness-marketplace

# 2. Install the plugin globally
claude plugin install harness@harness-marketplace
```

## Quick Start

```bash
# Diagnose your current project's harness
/harness:check-harness

# Scaffold a new project with AI-optimized structure
/harness:scaffold

# Clarify unclear requirements through structured interview
/harness:deep-interview "I'm not sure what to build"

# Turn a goal into a full implementation plan
/harness:specify "implement user authentication"

# QA test a running app
/harness:qa http://localhost:3000

# Check if your context docs are stale or contradictory
/harness:doc-drift
```

## Project Structure

```
.claude-plugin/
  marketplace.json      # Marketplace manifest (source: ./plugins/harness)
  plugin.json           # Plugin manifest
commands/               # Slash commands — one .md per skill
  qa.md
  check-harness.md
  scaffold.md
  specify.md
  deep-interview.md
  doc-drift.md
  agent-orchestrate.md
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
  harness -> ../        # Symlink for marketplace path resolution
.claude/
  settings.json
```

## How It Works

Commands in `commands/` delegate to their corresponding `skills/` file:

```
/harness:qa  →  commands/qa.md  →  reads skills/qa/SKILL.md
```

`skills/` files are the single source of truth for all skill logic. Edits take effect immediately — no reinstall needed.

## License

Internal use only.
