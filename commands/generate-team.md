---
description: "Design and build agent team architecture (delegates to harness-factory). Run when the user asks to 'generate team', 'build agent team', 'build agent pod', 'set up agent architecture', or 'create agent team'. If harness-factory is installed, reads its SKILL.md and executes it; otherwise shows an install guide."
argument-hint: "[project description or leave empty to scan CWD]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, Agent, Task, AskUserQuestion, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate]
---

This command delegates to the harness-factory plugin's `generate-team` skill.

**Step 1: Check harness-factory installation**

Use Bash to check the following paths in order:

1. `~/.claude/plugins/harness-factory/skills/generate-team/SKILL.md` (marketplace install path)
2. If not found, check whether the `~/.claude/plugins/harness-factory/` directory itself exists

**Step 2A: harness-factory is installed**

Read `~/.claude/plugins/harness-factory/skills/generate-team/SKILL.md` with the Read tool and follow its instructions exactly.

User arguments: $ARGUMENTS

**Step 2B: harness-factory is not installed**

Output the message below and stop:

---

**harness-factory plugin is not installed.**

`/harness-ops:generate-team` delegates to the harness-factory plugin. Install harness-factory first.

**Installation:**

```bash
# 1. Clone the harness-factory repository
git clone https://github.com/hyunhokim/harness-factory.git ~/.claude/plugins/harness-factory

# 2. Register the marketplace in Claude Code
claude plugin marketplace add ~/.claude/plugins/harness-factory

# 3. Install the plugin
claude plugin install harness-factory
```

After installation, run `/harness-ops:generate-team` or `/harness-factory:generate-team` again.

---
