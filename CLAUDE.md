# harness-ops — Project Rules

## Harness: Git Workflow

**Goal:** Automate the full commit-push-PR pipeline via a 3-agent team.

**Trigger:** When the user says "please commit", "commit this", "commit and push", "make a PR", "ship this", or similar — use the `git-commit` skill. Simple git status questions can be answered directly without the skill.

**Change history:**
| Date | Change | Target | Reason |
|------|--------|--------|--------|
| 2026-05-20 | Initial setup | git-analyst, git-operator, git-pr-agent | User requested automated commit/push/PR flow |
