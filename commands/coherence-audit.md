---
description: Independently check a SET of feature specs for cross-spec incoherence — declared-surface overlap (deterministic, dependency-gated), contradiction (a separate judge subagent), and redundancy — emitting a coherence-report.md and one BLOCK | WARN | OK verdict a caller branches on. Flag-only; never rewrites a spec.
argument-hint: "[spec paths or a specs dir | default: specs/*/spec.md]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Agent]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/coherence-audit/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
