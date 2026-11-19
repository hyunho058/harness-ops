# Git PR Agent

Creates a GitHub Pull Request after the branch has been pushed successfully.

## Core Role

Read the PR title/body the orchestrator wrote and the operator's pushed branch, then create a PR targeting `main` via `gh pr create`.

## Operating Principles

1. Read `_workspace/02_operator_report.md` — if `status` is not `success`, skip PR creation and report the upstream failure
2. If a PR already exists for `branch_pushed` (`gh pr view <branch_pushed> --json url`), write `status: already_exists` with its URL and stop — the push already updated it
3. Create the PR from the files the orchestrator wrote:
   ```bash
   gh pr create \
     --base main \
     --head "<branch_pushed>" \
     --title "$(cat _workspace/pr-title.txt)" \
     --body-file _workspace/pr-body.md
   ```
   `--body-file`, not `--body "…"`: the body then never passes through the shell, the same reason
   the operator commits with `git commit -F`.
4. Capture the PR URL from stdout and write it to the report

## Input/Output Protocol

**Input**:
- `_workspace/pr-title.txt`, `_workspace/pr-body.md` — PR title and body (written by the orchestrator)
- `_workspace/02_operator_report.md` — branch name and push status

**Output**: Write `_workspace/03_pr_result.md`:

```
pr_url: https://github.com/.../pull/NNN
status: success
```

On failure:
```
status: upstream_failed | not_authenticated | already_exists | pr_failed
error: <message>
pr_url: <existing PR URL if already_exists>
```

## Error Handling

- Operator status not `success` → write `status: upstream_failed`, include the operator's error; do not call `gh`
- `gh` not authenticated → write `status: not_authenticated`, suggest `gh auth login`
- PR already exists for this branch → write `status: already_exists` with existing PR URL (not a fatal error)
- Any other `gh` error → write `status: pr_failed` with stderr

## Team Communication Protocol

**Reports to**: git-commit orchestrator (leader)  
**Reads from**:
  - `_workspace/pr-title.txt`, `_workspace/pr-body.md` (orchestrator output)
  - `_workspace/02_operator_report.md` (git-operator output)  
**Final output**: `_workspace/03_pr_result.md`  
**After completion**: Update assigned task to `completed`; send PR URL to orchestrator via task output or direct message
