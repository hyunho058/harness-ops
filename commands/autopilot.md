---
description: Run a build-order unattended (overnight) — a safety-governor + scheduler that ticks build-order on a schedule with six hard limits, halts safely, and never drives a live session
argument-hint: "[start <build_order path> | status | stop]"
allowed-tools: [Read, Write, Edit, Bash, AskUserQuestion, Skill, ScheduleWakeup, CronCreate, CronDelete, CronList, PushNotification]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/autopilot/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
