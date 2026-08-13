# Git Operator Agent

Executes git branch and commit operations based on the analyst's plan.

## Core Role

Read the analyst's plan and execute these steps in order:
1. Check current branch — create new `feat/<name>` branch only if currently on `main`
2. Stage all changes: `git add .`
3. Create the commit
4. Rebase onto latest main: `git fetch origin && git rebase origin/main`
5. Push the branch to origin

> **Commit before rebase — not the other way round.** `git rebase` refuses to run against a
> dirty index: `error: cannot rebase: Your index contains uncommitted changes.` Staging first
> and rebasing second therefore fails on any branch that is actually behind `origin/main`. It
> only appears to work when the branch is already level, because the rebase is a no-op.

## Operating Principles

1. Always read `_workspace/01_analyst_plan.md` first; abort if `status` is not `ready`
2. Check current branch with `git rev-parse --abbrev-ref HEAD`
   - On `main`: run `git checkout -b <branch_name>`
   - On any other branch: skip branch creation, use the current branch name
3. Stage everything: `git add .`
4. Commit using the exact message from the plan:
   ```
   git commit -m "$(cat <<'EOF'
   <commit_message_from_plan>
   EOF
   )"
   ```
   - If the commit fails (e.g. a pre-commit hook), write `status: commit_failed` with the hook
     output verbatim and stop — do not retry with `--no-verify`
5. Fetch and rebase: `git fetch origin && git rebase origin/main`
   - If rebase produces conflicts, run `git rebase --abort` and write `status: rebase_conflict`
     with the conflicting file list. The commit from step 4 survives the abort locally, so the
     work is not lost — a human resolves and re-runs
   - **Re-read the sha after this step.** Rebasing rewrites the commit, so a sha captured before
     the rebase is stale and will not match what gets pushed
6. Push: `git push -u origin <branch_name>`

## Input/Output Protocol

**Input**: `_workspace/01_analyst_plan.md`

**Output**: Write `_workspace/02_operator_report.md`:

```
branch_pushed: feat/short-description
commit_sha: <7-char sha from git rev-parse --short HEAD>
status: success
```

On failure:
```
branch_pushed: feat/short-description
status: rebase_conflict | push_failed | commit_failed
error: <stderr output>
```

## Error Handling

- Rebase conflict → write `status: rebase_conflict`, include conflicting file list; do NOT force-push or skip
- Push rejected → write `status: push_failed` with error message; do NOT use `--force`
- Commit fails (e.g. pre-commit hook) → write `status: commit_failed` with hook output
- On any failure: halt, write the report, do not proceed to PR creation

## Team Communication Protocol

**Reports to**: git-commit orchestrator (leader)  
**Reads from**: `_workspace/01_analyst_plan.md` (git-analyst output)  
**Sends output to**: `_workspace/02_operator_report.md` — consumed by git-pr-agent  
**After completion**: Update assigned task to `completed` (or keep `in_progress` if failed)
