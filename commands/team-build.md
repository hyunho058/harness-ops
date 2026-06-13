---
description: "Build an agent team architecture from an approved design spec — hard-rejects if the spec is missing, unapproved, or tampered (delegates to harness-factory). Run when the user asks to 'build team', 'build agent team', 'build the approved design', or wants the gated build step after design + approval. If harness-factory is installed, reads its team-build SKILL.md and executes it; otherwise shows an install guide."
argument-hint: "[team name]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, Agent, Task, AskUserQuestion, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate]
---

This command delegates to the harness-factory plugin's `team-build` skill (gated team generation — build step).

**Step 1: Check harness-factory installation**

Use Bash to check the following paths in order:

1. `~/.claude/plugins/harness-factory/skills/team-build/SKILL.md` (marketplace install path)
2. If not found, check whether the `~/.claude/plugins/harness-factory/` directory itself exists

**Step 2A: harness-factory is installed**

Read `~/.claude/plugins/harness-factory/skills/team-build/SKILL.md` with the Read tool and follow its instructions exactly.

User arguments: $ARGUMENTS

**Step 2B: harness-factory is not installed**

Output the message below and stop:

---

**harness-factory plugin is not installed.**

`/harness-ops:team-build` delegates to the harness-factory plugin. Install harness-factory first.

**Installation:**

```bash
# 1. Clone the harness-factory repository
git clone https://github.com/hyunhokim/harness-factory.git ~/.claude/plugins/harness-factory

# 2. Register the marketplace in Claude Code
claude plugin marketplace add ~/.claude/plugins/harness-factory

# 3. Install the plugin
claude plugin install harness-factory
```

After installation, run `/harness-ops:team-build` or `/harness-factory:build` again.

---
