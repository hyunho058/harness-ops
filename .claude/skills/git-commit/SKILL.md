---
name: git-commit
description: "Git workflow orchestrator. Triggers on: 'please commit', 'commit this', 'commit and push', 'make a PR', 'create pull request', 'push and open PR', 'ship this', 'commit my changes', 'please push', 'make a commit'. Automates the full git flow: creates a feature branch (if on main), stages all changes, writes a Conventional Commits message, commits, rebases onto main, pushes the branch, and opens a GitHub PR. Also handles follow-up requests: 're-run commit', 'redo the PR', 'update commit message', 'retry push', 'fix the PR'. Do NOT trigger for: git status questions, reading git log, explaining diffs, or resetting/reverting changes."
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
| 2 | git-operator | Branch, commit, rebase, push | analyst plan | `_workspace/02_operator_report.md` |
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
      commit_message: |
        type(scope): description

        Optional body explaining why.

        <any attribution trailers this session requires, verbatim>
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
  description: "Git operator — branch, commit, rebase, push",
  prompt: "
    You are the git-operator agent.
    Read the full role definition at: <CWD>/.claude/agents/git-operator.md

    Task: read _workspace/01_analyst_plan.md and execute the git workflow.
    Project root: <CWD>

    Steps:
    1. Read _workspace/01_analyst_plan.md
    2. Check current branch (git rev-parse --abbrev-ref HEAD)
       - If 'main': git checkout -b <branch_name>
       - Otherwise: stay on current branch and IGNORE the plan's branch_name
    3. git add -A, then CONFIRM SCOPE: run `git status --short` and compare
       the staged set against the scope stated above. If anything outside it
       is staged, report status: unexpected_scope, do NOT commit, and stop.
       Use -A, not `git add .` — the latter stages only the subtree below the
       current directory, so running from a subdirectory silently commits a
       subset and makes this very check look clean.
    4. Commit from a FILE, never with -m. commit_message is a YAML block
       scalar (commit_message: |) — use the extraction snippet in step 4 of
       the role definition verbatim: strip the 2-space indent into
       _workspace/commit-message.txt, then `git commit -F` that file.
       Use that fixed path, NOT $(mktemp): each command runs in its own
       shell, so a variable holding a temp path is gone by the next call —
       including the amend fallback, which is the one recovery path that
       needs the file. _workspace*/ is gitignored, so it is never committed.
       Reading commit_message as a single line does NOT yield the subject: it
       yields the block indicator, the literal pipe character. Committing that
       gives a commit whose whole message is that one character — subject,
       body and trailers all gone. -m also exposes backticks, $ and quotes in
       the message to shell expansion.
       Guard first: if the extraction is empty or all whitespace, report
       status: empty_commit_message and stop WITHOUT committing — it means the
       plan has no commit_message block, or spells it without the `|`.
       Then verify MECHANICALLY, not by eye — use the diff in the role
       definition's step 4, which compares the stored message against the file
       with blank lines and trailing whitespace normalised away on both sides.
       Empty output means every line survived; any output is the exact
       discrepancy. If it differs, `git commit --amend -F
       _workspace/commit-message.txt` and re-compare BEFORE pushing.
       Do not substitute a grep for the two trailer lines: that passes a commit
       whose body was truncated.
    5. git fetch origin && git rebase origin/main
       (commit BEFORE rebase — git rebase refuses a dirty index:
        'error: cannot rebase: Your index contains uncommitted changes')
       (re-read the sha after this — rebasing rewrites the commit)
    6. Push the branch that is actually checked out — re-read it with
       `git rev-parse --abbrev-ref HEAD` and push THAT, never the plan's
       branch_name.
       Step 2 only checks out <branch_name> when starting from main. On any
       other branch it keeps the current one, while the analyst still proposes
       a feat/<short-description> name — usually a DIFFERENT one. In
       `git push origin <name>`, <name> names a LOCAL BRANCH to push; it does
       not mean 'push HEAD as <name>'. So the plan's name either fails with
       'error: src refspec <name> does not match any' and pushes nothing, or —
       if a local branch by that name happens to exist — silently pushes THAT
       branch instead, leaving the user's commit unpushed. When step 2 did
       create the branch, HEAD already equals <branch_name>, so re-reading is
       correct in every case.
       Report the re-read $BRANCH as branch_pushed.

    Write result to _workspace/02_operator_report.md
  "
)
```

> **The plan's `branch_name` is advisory once a feature branch is checked out.** It decides only
> whether step 2 creates a branch off `main`. From step 6 on, the branch that received the commit
> is the one to push and the one to report.

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

- **Success**: "Branch `<branch_pushed>` pushed. Commit: `<sha>`. PR: `<pr_url>`"
  (use `branch_pushed` from the operator report — the branch that actually received the commit,
  not the plan's `branch_name`)
- **Analyst failed**: "Could not determine what to commit. Details: `_workspace/01_analyst_plan.md`"
- **Operator failed**: describe the specific error (rebase conflict, push rejected, hook failure)
- **PR failed**: "Push succeeded but PR creation failed. Branch: `<branch_pushed>`. Error: `<message>`"

## Error Handling

| Error | Response |
|-------|----------|
| Nothing to commit | Stop at Phase 0 |
| `unexpected_scope` | Staged set exceeded the stated scope. Nothing was committed — say so, and list the unexpected paths |
| `empty_commit_message` | The `commit_message` block extracted to nothing. Nothing was committed. Point at `_workspace/01_analyst_plan.md`: the block is missing, or written without `\|` |
| Message verification differs | Operator amends with `-F` and re-compares; if it still differs, report as `commit_failed` with the diff |
| Rebase conflict | Abort the rebase; report files in conflict. The commit is already made and survives the abort — say so, so the user does not fear lost work |
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
2. git-analyst → writes `branch_name: feat/add-logging` and a `commit_message: |` block whose
   subject is `feat(logger): add structured logging`
3. git-operator → creates branch, commits, rebases, pushes
4. git-pr-agent → creates PR, returns URL
5. Report: "Branch `feat/add-logging` pushed. Commit: `a1b2c3d`. PR: https://github.com/.../pull/42"

### Commit message with a body and trailers

1. git-analyst → writes `commit_message: |` with a subject, a body paragraph, and two attribution
   trailers, each content line indented 2 spaces
2. git-operator → extracts the block, strips the indent to a temp file, runs `git commit -F`
3. Operator verifies `git log -1 --format=%B` contains the body and both trailer lines
4. Commit carries the full message

**The regression this guards** (verified): reading `commit_message` as a single line yields the
literal `|`, and `git commit -m '|'` produces a commit whose entire message is one pipe character.
`-m` also exposes backticks, `$` and quotes in the message to shell expansion.

### Already on a feature branch (the plan's name must not be pushed)

1. User has uncommitted changes on `feat/worktree-dual-runtime-support`, which has an open PR
2. git-analyst → proposes `branch_name: feat/remove-command-wrappers` (a *different* name)
3. git-operator → step 2 keeps the current branch, step 6 re-reads `HEAD` and pushes
   `feat/worktree-dual-runtime-support`
4. Report: "Branch `feat/worktree-dual-runtime-support` pushed …"

**The regression this guards** (both outcomes verified against a real remote): pushing the plan's
name instead fails with `error: src refspec feat/remove-command-wrappers does not match any`,
leaving the commit unpushed and the PR unchanged — and if a local branch by that name happens to
exist, the push succeeds on the **wrong** branch, publishing unrelated work while the user's commit
stays local.

### Error path: rebase conflict

1. Analyst writes plan successfully
2. Operator stages and **commits**, then hits a conflict during `git rebase origin/main`
3. Operator runs `git rebase --abort` and writes `status: rebase_conflict`
4. Phase 4 skipped; report: "Rebase conflict in `src/foo.ts`. Your commit is already made locally
   and survived the abort — nothing is lost. Resolve the conflict, then run 'please commit' again
   (it will find nothing new to stage and proceed to rebase + push)."
