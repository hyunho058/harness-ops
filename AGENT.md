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
commands/             # Slash commands for cross-plugin bridges only (harness-factory)
hooks/                # Lifecycle hooks (hooks.json registration + scripts)
plugins/
  harness-ops         # Symlink → ../ for marketplace path resolution
skills/               # Core skill implementations (SKILL.md per skill is the source of truth)
  check-harness/      # Harness maturity assessment
  scaffold/           # Greenfield project harness scaffolding
  specify/            # Goal → Implementation plan (spec.md)
  requirements-interview/     # Socratic requirements interview
  qa/                 # QA testing (browser/computer/cli)
  context-audit/          # Documentation drift audit
  agent-orchestrate/  # Agent orchestration patterns
.gemini/
  commands/harness-ops/ # Gemini CLI command definitions
```

## Development Guidelines

- **Skills**: The core logic of a skill is defined in `skills/{name}/SKILL.md`. This is the source of truth — edits take effect immediately without reinstalling the plugin.
- **Commands**: `skills/` are exposed as `/harness-ops:<name>` directly — do NOT add a `commands/*.md` wrapper for a skill in this repo, it only duplicates the entry in the slash menu. `commands/` is reserved for bridges to *other* plugins (harness-factory), which have no local skill to expose.
- **Agents**: Subagent definitions in `agents/` are consumed by skills (primarily `check-harness`). Each file defines a specialized subagent role.
- **Hooks**: The hook registry and scripts are managed under `hooks/hooks.json`.
- **Format**: All prompt outputs and specifications should use `.md` by default (e.g., `spec.md` not `spec.json`).
- **Cross-compatibility**: Skills must be designed to be universally invokable across Claude Code, Antigravity CLI (`agy`), and Gemini CLI. Avoid tool-specific APIs inside `SKILL.md` files — name a **capability** from `references/runtime-tools.md` instead (`` `capability:run-command` ``, not `Bash`). `scripts/portability-lint.sh` enforces this for every skill listed in `references/converted-skills.md`, and runs as a PreToolUse hook.
- **Gemini commands**: `.gemini/commands/harness-ops/*.toml` embed a copy of a `SKILL.md`. Never hand-edit the copy — edit the skill and run `scripts/gen-gemini-commands.sh <skill>`. `--check` reports drift. The generator also injects the path anchor that makes `../../references/…` resolvable from a Gemini command, whose cwd is the user's project rather than the skill directory.

## Installation

See `README.md` for plugin installation steps (`claude plugin marketplace add` / `claude plugin install`).
