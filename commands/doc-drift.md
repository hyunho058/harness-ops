---
description: Audits all context documents Claude loads (CLAUDE.md, MEMORY.md, skills, agents, plugins) for outdated claims, contradictions, and risky wording
argument-hint: "[recent [N] | path <glob>]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Agent]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/doc-drift/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
