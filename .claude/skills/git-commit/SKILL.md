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

You write the commit inputs yourself, then run git-operator → git-pr-agent as
sequential sub-agents to execute the commit-push-PR workflow.

## Execution Mode: Orchestrator writes inputs + Sub-agent (Sequential Pipeline)

```
You (orchestrator)        →  Agent(git-operator)  →  Agent(git-pr-agent)
        ↓                            ↓                        ↓
commit-message.txt,          02_operator_report.md      03_pr_result.md
pr-title.txt, pr-body.md
```

There is no separate analyst step. An agent that writes the commit message would be handed the
branch, the file scope, the attribution trailers and a description of the change before it
starts, so it would mostly reformat text that already exists — for a sub-agent round-trip per
commit. The `git-analyst` agent that did this, and git-operator's pipeline mode that read its
plan, were removed for that reason.

## Agent Composition

| Step | Who | Role | Input | Output |
|------|-------|------|-------|--------|
| 1 | You (orchestrator) | Read the diff, decide scope, write message and PR text | git state + the user's request | `_workspace/commit-message.txt`, `pr-title.txt`, `pr-body.md` |
| 2 | git-operator | Branch, commit, rebase, push | Scope + branch name + message file | `_workspace/02_operator_report.md` |
| 3 | git-pr-agent | Create GitHub PR | PR text files + operator report | `_workspace/03_pr_result.md` |

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

### Phase 2: Write the commit inputs yourself

Do this in the main session — do not spawn a sub-agent for it.

1. Read the change: `git status --short`, `git diff`, and `git diff --cached`.
2. Decide the **Scope** from the user's request: an explicit path/glob list, or the literal
   `all changes in the working tree` when they asked for everything with no narrowing. The
   request is the only place the intended scope exists — it cannot be recovered from the repo.
3. Decide a **branch name** `type/short-description`. It is used only if `HEAD` is `main`.
4. Write `_workspace/commit-message.txt` **with the Write tool**: a Conventional Commits subject,
   an optional body explaining why, then this session's attribution trailers, byte for byte, as
   the last lines. Use only the trailers the session provides (typically `Co-Authored-By:`, and
   `Claude-Session:` when given); when it provides none, add none. Never hard-code a model name.
5. Write `_workspace/pr-title.txt` (one line, usually the commit subject) and
   `_workspace/pr-body.md` (`## Summary` bullets, `## Test plan` checklist, then the session's
   pull-request attribution line verbatim if it provides one).

Use the Write tool rather than `echo` or a heredoc: the file is then the message byte for byte,
with no shell expansion and no YAML block scalar to extract.

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

    Task: commit, rebase and push.
    Project root: <CWD>
    Scope: <the files the user asked to commit — an explicit path/glob list, or the
            literal 'all changes in the working tree' when they asked for everything>
    Branch name if HEAD is main: <the branch name from Phase 2>
    Commit message: already written to _workspace/commit-message.txt — commit it
    as is; do not rewrite or reformat it.

    Steps:
    1. Guard: if _workspace/commit-message.txt is missing, empty or all
       whitespace, report status: empty_commit_message and stop WITHOUT
       committing.
    2. Check current branch (git rev-parse --abbrev-ref HEAD)
       - If 'main': git checkout -b <branch name above>
       - Otherwise: stay on current branch and IGNORE the proposed name
    3. git add -A, then CONFIRM SCOPE: run `git status --short` and compare
       the staged set against the `Scope:` line above — that line is the
       reference set. If it is missing, report status: missing_scope, do NOT
       commit, and stop: never treat "whatever git add -A staged" as the
       scope, which compares the staged set against itself and passes
       unconditionally. If anything outside the reference
       set is staged, report status: unexpected_scope, do NOT commit, and stop.
       List the staged paths in the report either way — `all changes in the
       working tree` is a legitimate scope but admits everything, so the report
       is where a human sees what it let through.
       Use -A, not `git add .` — the latter stages only the subtree below the
       current directory, so running from a subdirectory silently commits a
       subset and makes this very check look clean.
    4. Commit from the FILE, never with -m:
       `git commit -F _workspace/commit-message.txt`. That fixed path, not
       $(mktemp), is what the amend fallback re-reads — each command runs in
       its own shell, so a variable holding a temp path is gone by the next
       call. _workspace*/ is gitignored, so it is never committed. -m would
       also expose backticks, $ and quotes in the message to shell expansion.
       Then verify MECHANICALLY, not by eye — use the diff in the role
       definition's step 4, which compares the stored message against the file
       with blank lines and trailing whitespace normalised away on both sides.
       Read it by WHICH SIDE the differing lines are on. Empty output passes.
       Output with only `>` lines also PASSES — every intended line survived
       and a commit-msg hook appended to it; record the added lines. Only a
       `<` line is a failure: a line went missing or was altered. Then
       `git commit --amend -F _workspace/commit-message.txt` and re-compare
       BEFORE pushing; if a `<` line survives the amend, report commit_failed.
       Never report commit_failed for a non-empty diff that has no `<` line —
       a hook that appends reproduces the same diff after every amend, so that
       rule reports failure forever for a commit that is sitting on HEAD.
       Do not substitute a grep for the two trailer lines: that passes a commit
       whose body was truncated.
    5. git fetch origin && git rebase origin/main
       (commit BEFORE rebase — git rebase refuses a dirty index:
        'error: cannot rebase: Your index contains uncommitted changes')
       (re-read the sha after this — rebasing rewrites the commit)
    6. Push the branch that is actually checked out — re-read it with
       `git rev-parse --abbrev-ref HEAD` and push THAT, never the proposed
       branch name. If that re-read returns the literal string `HEAD`, the
       checkout is DETACHED: report status: detached_head with the short sha,
       do NOT push. `git push -u origin HEAD` is refused ("not a full
       refname"), and the commit sits on no branch, so say it exists and can
       be rescued with `git branch <name> <sha>`.
       Step 2 only checks out the proposed name when starting from main. On any
       other branch it keeps the current one, while the orchestrator still
       proposes a feat/<short-description> name — usually a DIFFERENT one. In
       `git push origin <name>`, <name> names a LOCAL BRANCH to push; it does
       not mean 'push HEAD as <name>'. So the proposed name either fails with
       'error: src refspec <name> does not match any' and pushes nothing, or —
       if a local branch by that name happens to exist — silently pushes THAT
       branch instead, leaving the user's commit unpushed. When step 2 did
       create the branch, HEAD already equals that name, so re-reading is
       correct in every case.
       Report the re-read $BRANCH as branch_pushed.
       Never force-push — the block-main-push hook refuses it on any branch.

    Write result to _workspace/02_operator_report.md
  "
)
```

> **The proposed branch name is advisory once a feature branch is checked out.** It decides only
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

    Task: create a GitHub PR for the branch the operator pushed.
    Project root: <CWD>

    Steps:
    1. Read _workspace/02_operator_report.md (branch_pushed, status)
    2. If operator status != 'success': write status: upstream_failed and stop
    3. If a PR already exists for branch_pushed (`gh pr view <branch_pushed>
       --json url`), write status: already_exists with its URL and stop — the
       push already updated it
    4. Run: gh pr create --base main --head <branch_pushed>
              --title "$(cat _workspace/pr-title.txt)"
              --body-file _workspace/pr-body.md
       (--body-file, not --body: the body never passes through the shell)
    5. Write result to _workspace/03_pr_result.md
  "
)
```

### Phase 5: Report

Read both report files and report to the user:

- **Success**: "Branch `<branch_pushed>` pushed. Commit: `<sha>`. PR: `<pr_url>`"
  (use `branch_pushed` from the operator report — the branch that actually received the commit,
  not the proposed branch name)
- **PR already existed**: "Branch `<branch_pushed>` pushed; it updated the existing PR `<pr_url>`"
- **Operator failed**: describe the specific error (rebase conflict, push rejected, hook failure)
- **PR failed**: "Push succeeded but PR creation failed. Branch: `<branch_pushed>`. Error: `<message>`"

## Error Handling

| Error | Response |
|-------|----------|
| Nothing to commit | Stop at Phase 0 |
| `missing_scope` | No scope reached the operator — the Phase 3 prompt had no `Scope:` line. Nothing was committed. Re-invoke Phase 3 with the scope stated |
| `unexpected_scope` | Staged set exceeded the stated scope. Nothing was committed — say so, and list the unexpected paths |
| `empty_commit_message` | `_workspace/commit-message.txt` is missing or blank. Nothing was committed. Rewrite it (Phase 2 step 4) and re-run Phase 3 |
| Message verification shows `<` lines | A line of the message is missing or altered. Operator amends with `-F` and re-compares; if a `<` line survives, report `commit_failed` with the diff |
| Message verification shows only `>` lines | A `commit-msg` hook appended to the message. This is a **pass** — report the commit as successful and mention the added lines |
| `detached_head` | `HEAD` is not on a branch. The commit was made and nothing was pushed. Give the short sha and tell the user to run `git branch <name> <sha>` before checking anything else out |
| Rebase conflict | Abort the rebase; report files in conflict. The commit is already made and survives the abort — say so, so the user does not fear lost work |
| Push rejected | Report rejection reason; never force-push (the block-main-push hook refuses it anyway) |
| `gh` not authenticated | Suggest `gh auth login` |
| Pre-commit hook failure | Show hook output; user must fix and re-run |

## Partial Re-run Support

When the user says "retry push", "redo PR", or "fix the commit message":
1. Check which `_workspace/0*` report shows a failure
2. Re-invoke only that agent (skip earlier steps); for "fix the commit message", rewrite
   `_workspace/commit-message.txt` and have the operator `git commit --amend -F` it
3. Overwrite only that output file

## Test Scenarios

### Happy path

1. User has uncommitted changes on `main`
2. Orchestrator → proposes `feat/add-logging` and writes `_workspace/commit-message.txt` whose
   subject is `feat(logger): add structured logging`
3. git-operator → creates branch, commits, rebases, pushes
4. git-pr-agent → creates PR, returns URL
5. Report: "Branch `feat/add-logging` pushed. Commit: `a1b2c3d`. PR: https://github.com/.../pull/42"

### Commit message with a body and trailers

1. Orchestrator → writes `_workspace/commit-message.txt` with the Write tool: a subject, a body
   paragraph, and the session's attribution trailers
2. git-operator → runs `git commit -F _workspace/commit-message.txt`
3. Operator diffs `git log -1 --format=%B` against the file (normalised) — no `<` lines
4. Commit carries the full message

**The regression this guards** (verified, under the old analyst pipeline): reading a
`commit_message: |` block as a single line yields the literal `|`, and `git commit -m '|'`
produces a commit whose entire message is one pipe character. Writing the message directly
removes that failure class — the message is written as a plain file, so there is no block scalar to extract.

**Be exact about the second reason, or it discredits the first.** `-m` is not unconditionally
unsafe: `git commit -m "$(cat <<'EOF' … EOF)"` with the delimiter **quoted** reproduces backticks,
`$HOME`, `$(…)` and both quote kinds byte for byte — tested. What does expand, also tested, is an
**unquoted** `<<EOF` (runs `$(…)` while building the heredoc) and a direct `-m "…"` (turns `$HOME`
into a path). So `-F` wins because it takes the requirement to remember that distinction off the
table entirely, and because the message then exists as a file the amend fallback can re-read.

### Already on a feature branch (the proposed name must not be pushed)

1. User has uncommitted changes on `feat/worktree-dual-runtime-support`, which has an open PR
2. Orchestrator → proposes `feat/remove-command-wrappers` (a *different* name)
3. git-operator → step 2 keeps the current branch, step 6 re-reads `HEAD` and pushes
   `feat/worktree-dual-runtime-support`
4. Report: "Branch `feat/worktree-dual-runtime-support` pushed …"

**The regression this guards** (both outcomes verified against a real remote): pushing the proposed
name instead fails with `error: src refspec feat/remove-command-wrappers does not match any`,
leaving the commit unpushed and the PR unchanged — and if a local branch by that name happens to
exist, the push succeeds on the **wrong** branch, publishing unrelated work while the user's commit
stays local.

### Scope narrower than the working tree

1. User says "commit the worktree skill fix"; the tree also holds unrelated edits to `scripts/`
2. Orchestrator writes `Scope: skills/worktree/**` into the Phase 3 prompt
3. git-operator → `git add -A` stages both; `git status --short` shows `scripts/` outside the scope
4. Operator writes `status: unexpected_scope` listing the `scripts/` paths and does **not** commit
5. Report: "Nothing was committed. These staged paths are outside the scope you asked for: …"

**The regression this guards:** the guard previously said to compare against "the scope stated
above" while nothing above stated one — the Phase 3 prompt carried only the task and project root,
and the plan's keys were `branch_name` / `commit_message` / `pr_title` / `pr_body` / `status`. With
no reference set the check resolves either way and both ways are wrong: compare against the staged
set itself and it passes unconditionally (a no-op guard that *reports* success, which is worse than
no guard), or treat the absence as a violation and every commit fails. The `Scope:` line is what
makes it a real comparison, and `missing_scope` is what keeps the undefined case loud.

### Error path: detached HEAD

1. The user's checkout is detached — an interrupted rebase, a `git checkout <sha>`, a bisect
2. git-operator → stages, commits, rebases; the commit is real and on `HEAD`
3. Step 6 re-reads the branch and gets the literal `HEAD`, so it writes `status: detached_head`
   with the short sha and does **not** push
4. Phase 4 skipped; report: "Commit `a1b2c3d` was made, but `HEAD` is detached, so it is on no
   branch and nothing was pushed. Run `git branch <name> a1b2c3d` to keep it before checking
   anything else out."

**The regression this guards** (verified against a real remote): `git rev-parse --abbrev-ref HEAD`
returns the string `HEAD` when detached, so the push becomes `git push -u origin HEAD` and git
refuses it with *"The destination you provided is not a full refname"*. Without the guard the
operator reports a generic `push_failed`, and the commit stays reachable only through the reflog.

### Error path: rebase conflict

1. Orchestrator writes the commit inputs
2. Operator stages and **commits**, then hits a conflict during `git rebase origin/main`
3. Operator runs `git rebase --abort` and writes `status: rebase_conflict`
4. Phase 4 skipped; report: "Rebase conflict in `src/foo.ts`. Your commit is already made locally
   and survived the abort — nothing is lost. Resolve the conflict, then run 'please commit' again
   (it will find nothing new to stage and proceed to rebase + push)."
