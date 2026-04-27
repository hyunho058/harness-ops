---
description: Detects drift between Claude memory and documentation — audits how far CLAUDE.md, memory, and specs deviate from the actual code reality
argument-hint: "[--memory|--claude-md|--spec|--all]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Agent]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/doc-drift/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
