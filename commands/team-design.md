---
description: "Design an agent team architecture — interview + design spec only, stops for human approval (delegates to harness-factory). Run when the user asks to 'design team', 'design agent team', 'design agent architecture', or wants the gated design step before build. If harness-factory is installed, reads its team-design SKILL.md and executes it; otherwise shows an install guide."
argument-hint: "[team name / project description or leave empty to scan CWD]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, Agent, Task, AskUserQuestion, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate]
---

This command delegates to the harness-factory plugin's `team-design` skill (gated team generation — design step).

**Step 1: Check harness-factory installation**

Use Bash to check the following paths in order:

1. `~/.claude/plugins/harness-factory/skills/team-design/SKILL.md` (marketplace install path)
2. If not found, check whether the `~/.claude/plugins/harness-factory/` directory itself exists

**Step 2A: harness-factory is installed**

Read `~/.claude/plugins/harness-factory/skills/team-design/SKILL.md` with the Read tool and follow its instructions exactly.

User arguments: $ARGUMENTS

**Step 2B: harness-factory is not installed**

Output the message below and stop:

---

**harness-factory plugin is not installed.**

`/harness-ops:team-design` delegates to the harness-factory plugin. Install harness-factory first.

**Installation:**

```bash
# 1. Clone the harness-factory repository
git clone https://github.com/hyunhokim/harness-factory.git ~/.claude/plugins/harness-factory

# 2. Register the marketplace in Claude Code
claude plugin marketplace add ~/.claude/plugins/harness-factory

# 3. Install the plugin
claude plugin install harness-factory
```

After installation, run `/harness-ops:team-design` or `/harness-factory:design` again.

---
