---
description: Orchestrate many feature specs through the loop as one resumable build — generate a topologically-ordered build_order.md, drive each ready feature via /loop, advance on green and park-and-continue on escalation
argument-hint: "[specs glob or manifest path | resume]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, AskUserQuestion, Skill, PushNotification]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/build-order/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
