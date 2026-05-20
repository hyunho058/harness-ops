---
name: git-commit
description: "Git workflow orchestrator. Triggers on: 'please commit', 'commit this', 'commit and push', 'make a PR', 'create pull request', 'push and open PR', 'ship this', 'commit my changes', 'please push', 'make a commit'. Automates the full git flow: creates a feature branch (if on main), stages all changes, rebases onto main, writes a Conventional Commits message, pushes the branch, and opens a GitHub PR. Also handles follow-up requests: 're-run commit', 'redo the PR', 'update commit message', 'retry push', 'fix the PR'. Do NOT trigger for: git status questions, reading git log, explaining diffs, or resetting/reverting changes."
allowed-tools:
  - Read
  - Bash
  - Write
  - Agent
  - TaskCreate
  - TaskUpdate
  - TeamCreate
  - TeamDelete
  - SendMessage
---

# Git Commit Orchestrator

Coordinates the git-analyst, git-operator, and git-pr-agent team to execute the full commit-push-PR workflow.

## Execution Mode: Agent Team (Pipeline)

## Agent Composition

| Member | Agent type | Role | Input | Output |
|--------|------------|------|-------|--------|
| git-analyst | general-purpose | Analyze diff, write commit plan | git state | `_workspace/01_analyst_plan.md` |
| git-operator | general-purpose | Branch, rebase, commit, push | analyst plan | `_workspace/02_operator_report.md` |
| git-pr-agent | general-purpose | Create GitHub PR | analyst plan + operator report | `_workspace/03_pr_result.md` |

## Workflow

### Phase 0: Context Check

1. Check whether `_workspace/` exists in the project root:
   - **Absent** → initial run, proceed to Phase 1
   - **Present + user requests retry/re-run** → partial re-run: re-invoke only the relevant agent
   - **Present + fresh "please commit"** → new run: rename `_workspace/` to `_workspace_<timestamp>/`, then proceed to Phase 1
2. Check git status briefly (`git status --short`) — if clean with nothing to commit, inform the user and stop

### Phase 1: Preparation

1. Create `_workspace/` in the project root (or ensure it exists for partial re-runs)
2. Note the current branch for reference

### Phase 2: Team Formation

Form the pipeline team:

```
TeamCreate(
  team_name: "git-team",
  members: [
    {
      name: "git-analyst",
      agent_type: "general-purpose",
      model: "opus",
      prompt: "You are the git-analyst agent. Read .claude/agents/git-analyst.md for your full role definition. Your task: analyze the current git state and write _workspace/01_analyst_plan.md. Project root: <CWD>."
    },
    {
      name: "git-operator",
      agent_type: "general-purpose",
      model: "opus",
      prompt: "You are the git-operator agent. Read .claude/agents/git-operator.md for your full role definition. Your task: read _workspace/01_analyst_plan.md and execute the git workflow (branch creation, rebase, commit, push). Project root: <CWD>."
    },
    {
      name: "git-pr-agent",
      agent_type: "general-purpose",
      model: "opus",
      prompt: "You are the git-pr-agent. Read .claude/agents/git-pr-agent.md for your full role definition. Your task: read _workspace/01_analyst_plan.md and _workspace/02_operator_report.md, then create the GitHub PR. Project root: <CWD>."
    }
  ]
)
```

### Phase 3: Task Assignment

Register pipeline tasks with explicit dependencies:

```
TaskCreate(tasks: [
  {
    title: "Analyze git state and write commit plan",
    description: "Run git status/diff/log. Write _workspace/01_analyst_plan.md with branch_name, commit_message, pr_title, pr_body, status.",
    assignee: "git-analyst"
  },
  {
    title: "Execute git workflow (branch, rebase, commit, push)",
    description: "Read _workspace/01_analyst_plan.md. Create branch if on main, git add ., rebase onto origin/main, commit, push. Write _workspace/02_operator_report.md.",
    assignee: "git-operator",
    depends_on: ["Analyze git state and write commit plan"]
  },
  {
    title: "Create GitHub Pull Request",
    description: "Read _workspace/01_analyst_plan.md and _workspace/02_operator_report.md. Run gh pr create. Write _workspace/03_pr_result.md with PR URL.",
    assignee: "git-pr-agent",
    depends_on: ["Execute git workflow (branch, rebase, commit, push)"]
  }
])
```

### Phase 4: Execution and Monitoring

1. git-analyst starts immediately. Wait for task completion.
2. Once analyst task completes: git-operator begins. Wait for completion.
3. Once operator task completes: check `_workspace/02_operator_report.md` status
   - If `success`: git-pr-agent begins
   - If any failure status: skip PR creation, jump to Phase 5 (report failure)
4. Once PR agent task completes: read `_workspace/03_pr_result.md`

### Phase 5: Cleanup and Report

1. Read the final state files:
   - `_workspace/01_analyst_plan.md` — commit message and branch name
   - `_workspace/02_operator_report.md` — commit SHA and push status
   - `_workspace/03_pr_result.md` — PR URL
2. TeamDelete("git-team")
3. Report to the user:
   - **Success**: branch name, commit SHA, PR URL
   - **Partial failure**: which step failed and what the error was
   - **Nothing to commit**: inform and suggest `git add` if files were forgotten

## Error Handling

| Error type | Response |
|------------|----------|
| Nothing to commit | Stop after Phase 0, inform user |
| Rebase conflict | Report conflicting files; suggest manual resolution then re-run |
| Push rejected | Report rejection reason; do NOT force-push |
| `gh` not authenticated | Report and suggest `gh auth login` |
| Pre-commit hook failure | Report hook output; user must fix and re-run |

Retry policy: each agent retries once internally on transient errors, then reports failure.

## Partial Re-run Support

When the user says "retry push", "redo PR", or "fix the commit message":
- Check which step failed from `_workspace/0*` files
- Re-invoke only that agent (skip earlier steps)
- Overwrite only the relevant output file

## Test Scenarios

### Happy path

1. User has uncommitted changes on `main`
2. git-analyst writes plan: `branch_name: feat/add-git-hooks`, `commit_message: feat(hooks): add pre-commit validation`
3. git-operator creates branch, rebases, commits, pushes
4. git-pr-agent creates PR, returns URL
5. Orchestrator reports: "Branch `feat/add-git-hooks` pushed. PR: https://github.com/.../pull/42"

### Error path: rebase conflict

1. Analyst writes plan successfully
2. Operator hits conflict during `git rebase origin/main`
3. Operator writes `status: rebase_conflict` with file list
4. Orchestrator skips PR creation, reports: "Rebase conflict in `src/foo.ts`. Resolve conflicts and run 'please commit' again."
