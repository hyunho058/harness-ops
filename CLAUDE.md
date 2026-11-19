# harness-ops — Project Rules

## Harness: Git Workflow

**Goal:** Commit, push, and open PRs directly, using `git-operator`'s procedure as the checklist.

**The flow.** The `git-commit` skill, in direct mode: write the commit message yourself — never
spawn `git-analyst`. Its load-bearing steps — `git add -A` scope check, `git commit -F` from
`_workspace/commit-message.txt`, mechanical message check, re-reading `HEAD` before push — each
caught a real defect here; don't skip them.

**Never force-push** (the `block-main-push` hook refuses it on any branch). On a rejected push or a
rebase conflict, report it and stop; a commit survives `git rebase --abort`, so say so rather than
leaving the user fearing lost work.

**Attribution:** end commit messages with the attribution trailers the session provides, verbatim —
whichever of `Co-Authored-By:` and `Claude-Session:` it gives. Use only those: never add a trailer the
session did not provide, and when it provides none, add none. Never hard-code a model name — it is
session-specific.
