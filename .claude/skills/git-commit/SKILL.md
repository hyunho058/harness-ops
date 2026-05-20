---
name: git-commit
description: "Git workflow orchestrator. Triggers on: 'please commit', 'commit this', 'commit and push', 'make a PR', 'create pull request', 'push and open PR', 'ship this', 'commit my changes', 'please push', 'make a commit'. Automates the full git flow: creates a feature branch (if on main), stages all changes, rebases onto main, writes a Conventional Commits message, pushes the branch, and opens a GitHub PR. Also handles follow-up requests: 're-run commit', 'redo the PR', 'update commit message', 'retry push', 'fix the PR'. Do NOT trigger for: git status questions, reading git log, explaining diffs, or resetting/reverting changes."
allowed-tools:
  - Read
  - Bash
  - Write
  - Agent
---

# Git Commit Orchestrator

Coordinates git-analyst → git-operator → git-pr-agent as sequential sub-agents to execute the full commit-push-PR workflow.

## Execution Mode: Sub-agent (Sequential Pipeline)

```
Agent(git-analyst)  →  Agent(git-operator)  →  Agent(git-pr-agent)
        ↓                       ↓                        ↓
01_analyst_plan.md    02_operator_report.md      03_pr_result.md
```

## Agent Composition

| Step | Agent | Role | Input | Output |
|------|-------|------|-------|--------|
| 1 | git-analyst | Analyze diff, write commit plan | git state | `_workspace/01_analyst_plan.md` |
| 2 | git-operator | Branch, rebase, commit, push | analyst plan | `_workspace/02_operator_report.md` |
| 3 | git-pr-agent | Create GitHub PR | analyst plan + operator report | `_workspace/03_pr_result.md` |

## Workflow

### Phase 0: Context Check

1. Run `git status --short`. If output is empty, tell the user there is nothing to commit and stop.
2. Check whether `_workspace/` exists:
   - **Absent** → initial run, proceed to Phase 1
   - **Present + user requests retry/re-run** → partial re-run: skip to the failed step
   - **Present + fresh "please commit"** → new run: `mv _workspace/ _workspace_<timestamp>/`, then proceed to Phase 1

### Phase 1: Preparation

Create `_workspace/` in the project root:

```bash
mkdir -p _workspace
```

### Phase 2: Run git-analyst

Invoke as a sub-agent and wait for it to complete before proceeding:

```
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  description: "Git analyst — analyze diff and write commit plan",
  prompt: "
    You are the git-analyst agent.
    Read the full role definition at: <CWD>/.claude/agents/git-analyst.md

    Task: analyze the current git state and write _workspace/01_analyst_plan.md.
    Project root: <CWD>

    Required output file format:
      branch_name: feat/short-description
      commit_message: type(scope): description
      pr_title: type(scope): description
      pr_body: |
        ## Summary
        - bullet 1
        - bullet 2

        ## Test plan
        - [ ] ...
      status: ready

    If nothing to commit, write: status: nothing_to_commit
  "
)
```

After the agent returns, read `_workspace/01_analyst_plan.md`. If `status: nothing_to_commit`, inform the user and stop.

### Phase 3: Run git-operator

Invoke only after Phase 2 succeeds:

```
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  description: "Git operator — branch, rebase, commit, push",
  prompt: "
    You are the git-operator agent.
    Read the full role definition at: <CWD>/.claude/agents/git-operator.md

    Task: read _workspace/01_analyst_plan.md and execute the git workflow.
    Project root: <CWD>

    Steps:
    1. Read _workspace/01_analyst_plan.md
    2. Check current branch (git rev-parse --abbrev-ref HEAD)
       - If 'main': git checkout -b <branch_name>
       - Otherwise: stay on current branch
    3. git add .
    4. git fetch origin && git rebase origin/main
    5. git commit -m '<commit_message>'
    6. git push -u origin <branch_name>

    Write result to _workspace/02_operator_report.md
  "
)
```

After the agent returns, read `_workspace/02_operator_report.md`. If `status` is not `success`, skip Phase 4 and jump to Phase 5 with the error.

### Phase 4: Run git-pr-agent

Invoke only after Phase 3 succeeds:

```
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  description: "Git PR agent — create GitHub pull request",
  prompt: "
    You are the git-pr-agent.
    Read the full role definition at: <CWD>/.claude/agents/git-pr-agent.md

    Task: create a GitHub PR using the analyst's plan and the operator's result.
    Project root: <CWD>

    Steps:
    1. Read _workspace/01_analyst_plan.md (pr_title, pr_body)
    2. Read _workspace/02_operator_report.md (branch_pushed, status)
    3. If operator status != 'success': write status: upstream_failed and stop
    4. Run: gh pr create --title '<pr_title>' --body '<pr_body>' --base main
    5. Write result to _workspace/03_pr_result.md
  "
)
```

### Phase 5: Report

Read all three workspace files and report to the user:

- **Success**: "Branch `<branch_name>` pushed. Commit: `<sha>`. PR: `<pr_url>`"
- **Analyst failed**: "Could not determine what to commit. Details: `_workspace/01_analyst_plan.md`"
- **Operator failed**: describe the specific error (rebase conflict, push rejected, hook failure)
- **PR failed**: "Push succeeded but PR creation failed. Branch: `<branch_name>`. Error: `<message>`"

## Error Handling

| Error | Response |
|-------|----------|
| Nothing to commit | Stop at Phase 0 |
| Rebase conflict | Report files in conflict; suggest manual resolution then re-run |
| Push rejected | Report rejection reason; never force-push |
| `gh` not authenticated | Suggest `gh auth login` |
| Pre-commit hook failure | Show hook output; user must fix and re-run |

## Partial Re-run Support

When the user says "retry push", "redo PR", or "fix the commit message":
1. Check which `_workspace/0*` file shows a failure
2. Re-invoke only that agent (skip earlier steps)
3. Overwrite only that output file

## Test Scenarios

### Happy path

1. User has uncommitted changes on `main`
2. git-analyst → writes `branch_name: feat/add-logging`, `commit_message: feat(logger): add structured logging`
3. git-operator → creates branch, rebases, commits, pushes
4. git-pr-agent → creates PR, returns URL
5. Report: "Branch `feat/add-logging` pushed. Commit: `a1b2c3d`. PR: https://github.com/.../pull/42"

### Error path: rebase conflict

1. Analyst writes plan successfully
2. Operator hits conflict during `git rebase origin/main`
3. Operator writes `status: rebase_conflict`
4. Phase 4 skipped; report: "Rebase conflict in `src/foo.ts`. Resolve manually then run 'please commit' again."
