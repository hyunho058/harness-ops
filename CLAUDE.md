# harness-ops — Project Rules

## Harness: Git Workflow

**Goal:** Commit, push, and open PRs directly, using `git-operator`'s procedure as the checklist.

**Trigger:** When the user says "please commit", "commit this", "commit and push", "make a PR",
"ship this", or similar — run the flow below. Simple git status questions, reading `git log`, and
explaining diffs need none of it.

**Do not spawn `git-analyst`.** Write the commit message yourself. By the time the analyst is
invoked it has already been handed the branch, the file scope, the attribution trailers, and a
description of the change, so it mostly reformats text that exists — at the cost of a subagent
round-trip per commit. This overrides Phase 2 of the `git-commit` skill, which still documents
that step.

**The flow.** `.claude/agents/git-operator.md` is the authoritative procedure, and it supports this
path directly: its step 1 has a **direct mode** for exactly this case, where you supply the message
and the scope yourself and there is no analyst plan to read. These are its load-bearing steps, each
of which caught a real defect in this repo:

1. **Confirm the scope before committing.** `git add -A` (never `git add .` — it stages only the
   subtree below the cwd), then `git status --short` and check the staged set against what the
   user actually asked for. Staging is the last point where a wrong-scope commit is free to undo.
2. **Commit from a file, never `-m`.** Write the message to `_workspace/commit-message.txt`
   (gitignored, and a fixed path survives between tool calls where a `$(mktemp)` variable does
   not), then `git commit -F` it. The defect this caught was a block scalar read as one line,
   committing the literal `|` as the whole message. State the shell-expansion half accurately:
   `-m "$(cat <<'EOF' … EOF)"` with a **quoted** delimiter is byte-exact and is *not* the hazard;
   an unquoted `<<EOF` and a direct `-m "…"` both expand `$` and `$(…)`. `-F` removes the need to
   remember which is which, and leaves the message on disk for the amend fallback.
3. **Verify the message mechanically.** Diff the committed message against that file with blank
   lines and trailing whitespace normalised away on both sides — `git commit` applies its own
   whitespace cleanup, so a raw diff false-fails. Judge the result by **which side** differs:
   empty passes, and so does output with only `>` lines, which is a `commit-msg` hook appending.
   Only a `<` line is a failure. A hook that appends reproduces its diff after every amend, so
   "any output is a failure" reports `commit_failed` forever for a commit that is on `HEAD`.
4. **Re-read `HEAD` before pushing.** Push the branch that is actually checked out. A proposed
   branch name is a refspec for a *local* branch, so pushing it either fails outright or silently
   pushes a different branch. If the re-read returns the literal `HEAD`, the checkout is detached:
   stop, give the short sha, and say the commit is on no branch until `git branch <name> <sha>`.
5. **Skip PR creation when a PR already exists** for the branch — pushing updates it. Only run
   `gh pr create` for a branch that has none.

**Never force-push.** On a rejected push or a rebase conflict, report it and stop; a commit
survives `git rebase --abort`, so say so rather than leaving the user fearing lost work.

**Attribution:** end commit messages with the `Co-Authored-By:` and `Claude-Session:` trailers the
session provides, verbatim. Never hard-code a model name — it is session-specific.

**Change history:**
| Date | Change | Target | Reason |
|------|--------|--------|--------|
| 2026-05-20 | Initial setup | git-analyst, git-operator, git-pr-agent | User requested automated commit/push/PR flow |
| 2026-09-15 | Drop the analyst phase; commit directly | git-analyst | User: the analyst reformats context it was already given, for a subagent round-trip per commit |
| 2026-09-15 | Record the operator's load-bearing steps here | git-operator | Three rounds of fixes this session; scope check, `-F` commit, message verification and `HEAD` re-read each caught a real defect |
| 2026-09-15 | Correct the `-m` rationale; accept hook-appended lines; guard detached `HEAD` | git-operator, git-commit | PR #26 review: a quoted heredoc through `-m` is byte-exact, so the old reason was disprovable; "any diff is a failure" reports `commit_failed` for a good commit under a `commit-msg` hook; `--abbrev-ref HEAD` yields `HEAD` when detached and the push is refused |
