---
name: worktree
argument-hint: "[create <branch> | list | attach <name> | remove <path>]"
description: |
  Create, list, attach, and remove git worktrees — each optionally backed by a
  detached tmux session — so you can run separate, independent Claude Code
  sessions on different branches in parallel without touching the work in your
  current session. Prepares an isolated sibling working directory, auto-copies
  untracked local config (.env, .claude/settings.local.json), spins up a tmux
  session running claude, and hands you the exact attach command.
  Use when: "/worktree", "worktree", "create a worktree", "list worktrees",
  "clean up worktrees", "remove a worktree", "worktree attach", "parallel session",
  "isolated workspace", "separate session", "new workspace", "work on a branch
  separately", "tmux session", "attach session".
  Do NOT trigger for: questions about the Agent `isolation: "worktree"` option
  (that is a temporary in-session agent worktree, a different thing), or general
  git branch questions that do not involve a separate working directory.
allowed-tools:
  - Read
  - Glob
  - Bash
  - AskUserQuestion
---

# /worktree — Isolated Parallel Session Workspaces

Manage `git worktree` directories whose purpose is to let the user run a **second,
fully independent Claude Code session** on another branch — with zero interference
with the files or uncommitted changes in the current session.

A worktree shares the repo's `.git` (commits, branches, objects) but has its **own
working directory**. So two sessions in two worktrees cannot touch each other's files.

When **tmux** is available, this skill also spins up a **detached tmux session** in
the new worktree and launches `claude --dangerously-skip-permissions` inside it — so
the parallel session is already live, never stalls on approval prompts, and the user
only has to `tmux attach`.

---

## Important Constraints (read before acting)

1. **A skill cannot *attach* you to a terminal session, but with tmux it CAN start
   one.** `tmux new-session -d` creates a live, detached session (with
   `claude --dangerously-skip-permissions` already running) from this non-interactive
   context. What still requires the user's own terminal is **attaching** to it — so
   Create ends by printing the exact `tmux attach` command. Without tmux, fall back to
   printing `cd … && claude --dangerously-skip-permissions` for the user to run in a
   new terminal. Never claim to have *attached* a session.
2. **A branch can be checked out in only one worktree at a time.** Always create a
   **new** branch with `-b` for a fresh workspace, unless the user names an existing
   branch that is not checked out anywhere.
3. **Worktrees and tmux sessions are NOT auto-deleted.** Worktrees persist on disk
   until `git worktree remove`; tmux sessions persist until `tmux kill-session` (or a
   reboot). That is why the `remove` subcommand cleans up both.
4. **Only `.git`-tracked content is checked out.** Gitignored config (`.env`, local
   settings) does not follow automatically — this skill copies a safe allowlist.

---

## tmux Availability (check once, up front)

Detect tmux before doing tmux-specific work:
```bash
command -v tmux >/dev/null 2>&1 && echo "tmux: yes" || echo "tmux: no"
```
- **Present** → use the tmux flow (auto-start a detached session running `claude`).
- **Absent** → degrade gracefully: do the plain worktree flow and print the manual
  `cd … && claude` launch command. Mention tmux is not installed and that
  `brew install tmux` unlocks auto-started parallel sessions. Do not error out.

**tmux session name** is derived from the workspace and must be tmux-safe (no `.`/`:`):
```bash
SESSION=$(printf '%s' "<REPO>-<slug>" | tr ' .:/' '----')
```
Correlate sessions to worktrees by their **path** (robust against name munging):
```bash
tmux list-sessions -F '#{session_name}	#{session_path}	#{session_attached}' 2>/dev/null
```

---

## Argument Parsing

Inspect the invocation argument and route to a subcommand:

| Argument starts with | Subcommand |
|----------------------|------------|
| `list`, `ls` | **List** |
| `attach`, `at` | **Attach** (rest = session/branch name) |
| `remove`, `rm`, `delete` | **Remove** |
| anything else that reads as a branch name — **ASCII, no whitespace** | **Create** (rest = branch name) |
| anything else — **non-ASCII, or containing whitespace** | **Ask first** via AskUserQuestion; do **NOT** create. See the guard below. |
| empty | Ask the user which action (create / list / attach / remove) via AskUserQuestion |

> **Guard — never auto-create from an implausible branch name.** `Create` is the
> catch-all, so *any* unrecognized argument would otherwise become a new branch plus a
> worktree directory and a tmux session — a side effect that is tedious to undo and easy
> to trigger by a simple typo (`/worktree lst`) or by a non-English subcommand alias
> this skill no longer parses — the localized aliases for list / attach / remove were
> removed in favour of the English spellings above. When the argument is non-ASCII or
> contains whitespace, treat it as **probably not a branch name**: ask the user whether
> they meant a subcommand or genuinely want a branch by that name, and proceed only on
> their answer. A non-ASCII branch name is perfectly legal in git, so this is a
> confirmation, **not** a rejection.

---

## Subcommand: Create

### 1. Gather inputs
```bash
ROOT=$(git rev-parse --show-toplevel)
REPO=$(basename "$ROOT")
```
- **Branch name**: from the argument if given. If absent, ask the user for a branch
  name via AskUserQuestion (do not invent one silently).
- **Slug**: sanitize the branch name for a filesystem path — replace `/` and spaces
  with `-` (e.g. `feature/foo bar` → `feature-foo-bar`).
- **Target path**: sibling of the repo → `../<REPO>-<slug>`.

### 2. Safety checks (stop with a clear message if any fail)
- Target path must not already exist.
- If the branch already exists, verify it is **not** checked out in another worktree
  (`git worktree list`). If it is, stop and explain.

### 3. Create the worktree
- New branch (default):
  ```bash
  git worktree add "../<REPO>-<slug>" -b "<branch>"
  ```
- Existing, non-checked-out branch (omit `-b`):
  ```bash
  git worktree add "../<REPO>-<slug>" "<branch>"
  ```

### 4. Auto-copy untracked local config
Copy each of these from `$ROOT` into the new worktree **if it exists**, preserving
the relative path. This is a fixed allowlist — never copy `node_modules`, build
output, or arbitrary ignored files.
```
.env
.env.local
.env.development
.env.production
.claude/settings.local.json
```
For each that exists, create the parent dir in the target and copy it. Report which
files were copied (and that they are gitignored, so they will never be committed and
will disappear when the worktree is removed).

### 5. Start a tmux session (if tmux is available)
Resolve the absolute target path and a tmux-safe `SESSION` name, guard against a name
collision, then start a **detached** session and launch `claude` in it:
```bash
TARGET=$(cd "../<REPO>-<slug>" && pwd)
SESSION=$(printf '%s' "<REPO>-<slug>" | tr ' .:/' '----')

if tmux has-session -t "$SESSION" 2>/dev/null; then
  # Name already taken — append a short suffix and retry, or stop and report.
  SESSION="${SESSION}-$(date +%H%M%S)"
fi

tmux new-session -d -s "$SESSION" -c "$TARGET"   # detached, cwd = worktree
tmux send-keys -t "$SESSION" 'claude --dangerously-skip-permissions' C-m   # pre-warm
```
The session is now **live** with `claude` running. It launches with
**`--dangerously-skip-permissions`** so the parallel session never stalls on the
"trust this directory?" prompt or repeated file/tool-approval prompts — file
create/edit/write and bash run without confirmation. This matches oh-my-claudecode
PSM behavior; the trade-off is that the session bypasses **all** permission guards, so
only use it in worktrees of repos you trust.
- To make it safer instead, swap the flag for `--permission-mode acceptEdits`
  (auto-accepts file edits but still confirms dangerous bash).
- If the user explicitly said they only want a shell, skip the `send-keys` line.

### 6. Hand off
**With tmux** — the session is already running; print the attach command:
```bash
tmux attach -t <SESSION>
```
If the user is already inside tmux (`$TMUX` is set), give the in-tmux form instead:
```bash
tmux switch-client -t <SESSION>     # or press Ctrl-b s and pick it
```
**Without tmux** — print the manual launch command for a new terminal (same
bypass-permissions behavior as the tmux path):
```bash
cd ../<REPO>-<slug> && claude --dangerously-skip-permissions
```
Either way, remind them: this new session is fully isolated; the current session's
branch and uncommitted changes are untouched.

---

## Subcommand: List

```bash
git worktree list
```
If tmux is available, also pull live sessions and correlate by path:
```bash
tmux list-sessions -F '#{session_name}	#{session_path}	#{session_attached}' 2>/dev/null
```
Present a combined, readable table: **path · branch · HEAD · tmux session · live?**
- Match each worktree path to a `session_path` to fill the tmux columns.
- `live?` = whether a session exists (and `attached` if someone is in it).
- Mark which entry is the **current** worktree (`$ROOT`).

If tmux is not installed, just show the plain `git worktree list` table and note that
tmux session columns are unavailable.

---

## Subcommand: Attach

The skill cannot take over the terminal, so it resolves the right session and prints
the command for the user to run.

### 1. Resolve the session
- From the argument (a session name, or a branch/slug to be matched).
- List candidate sessions that belong to **this repo's** worktrees by correlating
  `tmux list-sessions` paths with `git worktree list` paths.
- If the argument is missing or ambiguous, show the candidates and ask which one via
  AskUserQuestion.
- If tmux is not installed, or there is no session for that worktree, say so and offer
  to **Create** one (or print `cd <path> && claude`).

### 2. Print the attach command
```bash
tmux attach -t <SESSION>
```
If already inside tmux (`$TMUX` set), print `tmux switch-client -t <SESSION>` instead.

---

## Subcommand: Remove

### 1. Resolve target
- From the argument (a path or branch). If ambiguous or missing, show
  `git worktree list` and ask the user which one via AskUserQuestion.
- Never remove the **current** worktree (`$ROOT`). Refuse and explain.
- Resolve the worktree's absolute path for correlation below.

### 2. Safety: check for uncommitted work
```bash
git -C "<path>" status --porcelain
```
- **Clean** → proceed.
- **Dirty** → list the changes and ask for explicit confirmation via AskUserQuestion
  ("Discard uncommitted changes in this worktree?"). Only on confirmation use
  `--force`.

### 3. Kill the bound tmux session (confirm first)
Find a session whose path matches the worktree, then **ask before killing** — it may
be running a live `claude`:
```bash
SESSION=$(tmux list-sessions -F '#{session_name}	#{session_path}' 2>/dev/null \
          | awk -F'\t' -v p="<abs-path>" '$2==p{print $1}')
```
- If a session is found, tell the user (note it may be running claude) and confirm via
  AskUserQuestion. On confirmation:
  ```bash
  tmux kill-session -t "$SESSION"
  ```
- If none is found (or tmux absent), skip this step silently.

### 4. Remove and prune
```bash
git worktree remove "<path>"        # add --force only if confirmed dirty
git worktree prune
```

### 5. Offer branch cleanup
Ask whether to also delete the branch that worktree was on (`git branch -d <branch>`,
or `-D` if unmerged and confirmed). Do not delete branches without asking.

---

## Rules

1. **Never claim to have *attached* a session** — only the user can attach in their own
   terminal. With tmux you *do* start the detached session; end Create/Attach by
   printing the `tmux attach` (or `switch-client`) command. Without tmux, print
   `cd … && claude --dangerously-skip-permissions`.
2. **Always `-b` for new workspaces** — avoid the "branch already checked out" error.
3. **tmux is optional, not required** — detect it once; degrade gracefully to the
   manual launch flow when it is absent. Never fail just because tmux is missing.
4. **New sessions launch with `--dangerously-skip-permissions`** (both the tmux and
   manual paths) so they never stall on trust/approval prompts — matching PSM. This
   bypasses all permission guards; it is intended for trusted repos. The safer
   alternative is `--permission-mode acceptEdits`.
5. **Session names are tmux-safe and collision-checked** — strip `.`/`:`/`/`/spaces;
   if the name is taken, suffix it. Correlate sessions to worktrees by **path**.
6. **Config copy is a fixed allowlist** — never copy `node_modules` or unknown ignored
   files; report exactly what was copied.
7. **Removal is guarded** — check for uncommitted changes first; `--force` only after
   explicit confirmation; **confirm before killing a live tmux session**; never remove
   the current worktree.
8. **Branches are never deleted silently** — always ask.
9. **Keep output tight** — the user wants the workspace ready and the attach (or
   launch) command, not an essay.
