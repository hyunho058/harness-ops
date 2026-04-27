# Harness

A global repository for skills and commands that can be utilized across various AI agent environments (Claude Code, Gemini CLI, IDE Assistants, etc.).
It contains templates and logic to maintain a consistent Harness infrastructure across all projects.

> **README.md** is the user-facing plugin installation guide. **AGENT.md** (this file) is the contributor/developer reference.

## Project Structure

```text
.claude/              # Claude Code project config (settings.json, skill stubs)
.claude-plugin/       # Plugin manifests (marketplace.json, plugin.json)
agents/               # Subagent definitions used internally by skills
  context-quality-reviewer.md    # Reviews CLAUDE.md and context document quality
  project-automation-auditor.md  # Audits hooks, automations, and workflow integrations
  session-pattern-analyzer.md    # Analyzes execution patterns from session history
  skill-portfolio-analyzer.md    # Evaluates installed skills coverage and gaps
commands/             # Slash command entry points — one .md per skill
hooks/                # Lifecycle hooks (hooks.json registration + scripts)
plugins/
  harness             # Symlink → ../ for marketplace path resolution
skills/               # Core skill implementations (SKILL.md per skill is the source of truth)
  check-harness/      # Harness maturity assessment
  scaffold/           # Greenfield project harness scaffolding
  specify/            # Goal → Implementation plan (spec.md)
  deep-interview/     # Socratic requirements interview
  qa/                 # QA testing (browser/computer/cli)
  doc-drift/          # Documentation drift audit
  agent-orchestrate/  # Agent orchestration patterns
```

## Development Guidelines

- **Skills**: The core logic of a skill is defined in `skills/{name}/SKILL.md`. This is the source of truth — edits take effect immediately without reinstalling the plugin.
- **Commands**: Slash commands live in `commands/` and delegate entirely to the corresponding `skills/` file. Each command file should do nothing except load and invoke its skill.
- **Agents**: Subagent definitions in `agents/` are consumed by skills (primarily `check-harness`). Each file defines a specialized subagent role.
- **Hooks**: The hook registry and scripts are managed under `hooks/hooks.json`.
- **Format**: All prompt outputs and specifications should use `.md` by default (e.g., `spec.md` not `spec.json`).
- **Cross-compatibility**: Skills must be designed to be universally invokable across Claude Code and Gemini CLI. Avoid tool-specific APIs inside `SKILL.md` files.

## Installation

See `README.md` for plugin installation steps (`claude plugin marketplace add` / `claude plugin install`).
