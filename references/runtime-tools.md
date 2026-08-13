# Runtime Tool Map — the portability contract

**Read this before executing any step of a skill that links here.**

harness-ops skills are written to run under more than one agent runtime. Skill bodies name
**capabilities**, never runtime tool names. This file is the single place where a capability
becomes a concrete procedure for the runtime you are actually running in.

Supported runtimes: **Claude Code** (primary) and **Antigravity CLI `agy`** (v1.1.11+).

---

## How to use this file

1. Determine your runtime. If your tools are named `Read` / `Write` / `Bash`, you are on Claude
   Code. If they are named `view_file` / `write_to_file` / `run_command`, you are on agy.
2. When a skill names a capability, look up its id below and perform **your runtime's column**.
3. When a skill cites a **procedure id** (rather than prose), the pinned procedure is mandatory —
   run it exactly. Do not substitute your own reasoning for it.

---

## Citation syntax

A skill cites an entry by writing its id in backticks with a `capability:` prefix:

```
Compute the intersection via `capability:run-glob-overlap`.
Load the spec with `capability:read-file`.
```

The prefix is what makes citations machine-checkable — the linter verifies every cited id exists
here, and the converted-list verifies that determinism-critical ids have not been quietly rewritten
back into prose.

<!-- BEGIN CANONICAL-IDS — parsed by scripts/portability-lint.sh; one id per line -->
```
read-file
write-file
edit-file
search-content
list-paths
run-command
ask-user
notify-user
fetch-url
search-web
track-tasks
schedule-wakeup
resolve-harness-root
run-glob-overlap
run-entry-digest
run-portability-tests
read-declared-surface-schema
spawn-named-checker
spawn-inline-checker
```
<!-- END CANONICAL-IDS -->

---

## Entry schema

Every entry declares four things:

| Field | Meaning |
|---|---|
| `id` | The capability/procedure id. One namespace — skills cite these ids. |
| `claude-code` | The procedure under Claude Code. |
| `agy` | The procedure under agy. |
| `determinism-critical` | `true` → the outcome depends on running exactly this; substitution is a defect. |

`determinism-critical: true` entries come in two classes:

- **pinnable** — both runtimes execute the same bytes (a shipped script). Parity is by construction.
- **divergent** — the procedures genuinely differ (subagent spawning). Parity cannot be pinned, so
  these entries additionally require an **artifact + registry assertion** (see `spawn-named-checker`).

**The vocabulary is closed.** A skill may only cite an id defined here. Adding a capability means
adding an entry, not inventing prose at a call site.

---

## General capabilities — `determinism-critical: false`

| id | claude-code | agy |
|---|---|---|
| `read-file` | `Read` | `view_file` |
| `write-file` | `Write` | `write_to_file` |
| `edit-file` | `Edit` | `replace_file_content` (or `multi_replace_file_content` for batched edits) |
| `search-content` | `Grep` | `grep_search` |
| `list-paths` | `Glob` | `list_dir`, narrowing with `grep_search` — **agy has no glob tool**; never pass an unexpanded `**` pattern to a tool expecting a literal path |
| `run-command` | `Bash` | `run_command` |
| `ask-user` | `AskUserQuestion` | `ask_question` |
| `notify-user` | `PushNotification` | `send_message` |
| `fetch-url` | `WebFetch` | `read_url_content` |
| `search-web` | `WebSearch` | `search_web` |
| `track-tasks` | `TaskCreate` / `TaskUpdate` | `manage_task` |
| `schedule-wakeup` | `ScheduleWakeup` / `CronCreate` | `schedule` (different contract — confirm semantics before relying on it) |

### Path rule (applies to every entry above)

- **Files you read** are addressed relative to the skill's own directory: `references/x.md`, or
  `../../references/x.md` for repo-root files. Never relative to the current working directory —
  under agy the cwd is the *user's* project, not this repo.
- **Shell arguments** cannot use a skill-relative path, because the shell resolves it against that
  same user cwd. They must use an absolute path built from `resolve-harness-root` below.

---

## `resolve-harness-root` — `determinism-critical: true` (pinnable)

Yields the absolute path to the harness-ops repository root, for use as a **shell argument**.

| Runtime | Procedure |
|---|---|
| Claude Code | `${CLAUDE_PLUGIN_ROOT}` |
| agy | Two-level ascent from the skill's own absolute directory: a skill lives at `<root>/skills/<name>/`, so `<root>` is `<skill-dir>/../..` |

**Validation is mandatory before use.** A guessed root that happens to exist is worse than none:

```
test -d "<root>/skills" && test -d "<root>/agents" && test -f "<target-script>"
```

If validation fails, **halt** — mark the affected tier `unverified` and BLOCK (see
`## Halting` below). Never fall back to reasoning about what the script would have returned.

> **Note on the symlink.** `plugins/harness-ops -> ../` means `<root>/plugins/harness-ops/skills/<name>`
> is an equally valid skill directory whose ascent yields a *different path string* for the *same*
> files. Compare script **output**, never path strings.

---

## Pinned script procedures — `determinism-critical: true` (pinnable)

These exist so the result is **run, not reasoned about**. Both runtimes execute identical bytes,
which is what makes two skills agree on the same input.

### `run-glob-overlap`
Deterministic glob-set intersection. Note the globs are handled **symbolically** — they are never
expanded against the filesystem, so this is not a filesystem query.

```
<root>/skills/coherence-audit/scripts/glob-overlap.sh <surface-a-file> <surface-b-file>
```

### `run-entry-digest`
Manifest entry digest.

```
<root>/skills/coherence-audit/scripts/entry-digest.sh <partition-manifest.md> <feature-id>
<root>/skills/coherence-audit/scripts/entry-digest.sh --canonical <partition-manifest.md> <feature-id>
```

### `run-portability-tests`
The repo's test runner, including the portability sweep.

```
<root>/skills/coherence-audit/scripts/run-tests.sh
```

Invoke all three via `run-command`, with `<root>` from `resolve-harness-root`.

> Under agy, `run_command` is **auto-denied in headless `-p` mode** ("a tool required the 'command'
> permission that headless mode cannot prompt for"). That is a *permission denial*, not a missing
> capability — see `## Halting`.

---

## `read-declared-surface-schema` — `determinism-critical: true` (pinnable)

The declared-surface normalization rules that verdicts depend on. Distinct from `read-file`
precisely because substituting a paraphrase here changes outcomes.

| Runtime | Procedure |
|---|---|
| Claude Code | `Read` → `../../skills/coherence-audit/references/declared-surface-schema.md` |
| agy | `view_file` → same skill-relative path |

---

## `spawn-named-checker` — `determinism-critical: true` (**divergent**)

Runs a named analyzer as a *separate* agent. The separation is the point: it is what makes the
result a check rather than the author grading their own work.

| Runtime | Procedure |
|---|---|
| Claude Code | `Agent(subagent_type="<name>")` — native discovery reads `agents/<name>.md` |
| agy | 1. `read-file` → `../../agents/<name>.md`<br>2. Strip **`tools:`** and any other Claude Code-only frontmatter key. **Keep `name:` and `description:`** — they carry the role contract (what it reads, what it returns, that it is read-only) and become `define_subagent`'s name and description parameters.<br>3. `define_subagent` with that name, description, and the body<br>4. `invoke_subagent` with the prompt |

**Why the strip:** `agents/*.md` declare `tools: Read, Grep, Glob, Bash`. agy's *skill parser*
ignores frontmatter, but here the text is hand-fed as a prompt — an unstripped `tools:` list
instructs the subagent to use tools that do not exist. Stripping the *whole* block instead would
discard `name`/`description` and with them the read-only constraint, so strip keys, not the block.

### Required assertion (divergent entries only)

Because the procedures differ, parity cannot be guaranteed by construction. A caller must verify
**both**:

1. **Artifact** — the analyzer's named report exists (`SESSION_REPORT`, `CONTEXT_REPORT`,
   `AUTOMATION_REPORT`, or the skill-portfolio report).
2. **Registry** — under agy, `manage_subagents` shows the named analyzer as defined and invoked.

Artifact existence alone is **not** sufficient: a main agent that skips delegation entirely and
writes a well-formed report in-context produces an indistinguishable file. Only the registry check
distinguishes real delegation from self-authored output.

---

## `spawn-inline-checker` — `determinism-critical: true` (**divergent**)

For a checker that has **no `agents/<name>.md` file** — its prompt is written inline at the call
site (coherence-audit's contradiction judge is the only current case). Separate from
`spawn-named-checker` because that procedure's step 1 sources a body from `../../agents/`, which
is unsatisfiable here; a skill citing the wrong one leaves the runtime to improvise, which is the
substitution these ids exist to prevent.

| Runtime | Procedure |
|---|---|
| Claude Code | `Agent(subagent_type="general-purpose")` with the inline prompt |
| agy | `define_subagent` with a role name, a description stating it is an independent judge, and the inline prompt as its body → then `invoke_subagent` |

Same assertion requirement as `spawn-named-checker` above, minus the artifact clause: there is no
named report file, so the **registry check is the only evidence** that the judgement came from a
separate context rather than the caller grading its own work.

---

## Halting

When a required procedure is unavailable, **halt with a named message**. Do not continue
best-effort and do not silently substitute — a partial result that looks complete is worse than a
refusal, because nothing downstream can tell the difference.

Skills with a tiered verdict (coherence-audit) reuse the shipped mechanism: mark the affected tier
`unverified`, which forces **BLOCK**.

The message must state **which** of these occurred:

| Condition | Message must say |
|---|---|
| The tool does not exist in this runtime | `unavailable: <procedure> not provided by <runtime>` |
| The tool exists but was denied | `denied: <procedure> requires permission not granted (e.g. agy headless -p auto-denies run_command)` |
| Root validation failed | `unresolved: harness root did not validate at <path>` |

Collapsing these into one message makes every failure ambiguous — a denial reads as a missing
capability, and the fix for each is different.

---

## For skill authors

- Cite capability ids, never runtime tool names.
- Cite a **procedure id** wherever the outcome depends on exactly how the step runs.
- Declare required procedure ids in the converted-list so the sweep can assert they still appear.
- Adding a runtime means adding a column here — not editing skills.
