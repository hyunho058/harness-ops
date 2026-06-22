---
description: Run a task as a supervised verification loop — 3 gates (Pass/Fail, Quantitative, Qualitative), iterate until they pass, escalate at autonomy boundaries
argument-hint: "[task or goal]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, AskUserQuestion, Agent, PushNotification]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/loop/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
