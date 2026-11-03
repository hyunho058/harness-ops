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
invoke-skill
resolve-harness-root
list-agents
run-glob-overlap
run-entry-digest
run-portability-tests
read-declared-surface-schema
spawn-named-checker
spawn-inline-checker
spawn-worker
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
  these entries additionally require an **evidence assertion** — the spawn's return and, under
  agy, the subagent registry; each entry states its own rule.

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

## `invoke-skill` — `determinism-critical: false`

Hands control to another harness-ops skill with a request string (`args`), in the same session.

| Runtime | Procedure |
|---|---|
| Claude Code | `Skill(skill="harness-ops:<name>", args="<args>")` |
| agy | agy has no skill-call tool. 1. `read-file` → `../../skills/<name>/SKILL.md` (skill-relative, per the path rule). 2. Follow that file from its first step, in this session, treating `<args>` as the user's invocation of it. |

**`<args>` is passed verbatim.** Under agy, `<args>` *is* the invocation the loaded skill sees, so
a marker in it (`mode: unattended`, `mode: batch`) counts as carried by the invocation exactly as
it would through `Skill`. Do not summarise or paraphrase it. Markers that also need a matching
record on disk (the spec's `## Meta`) are still checked against that record by the loaded skill.

If the file cannot be read, halt with `unresolved: harness root did not validate at <path>`, naming
the path tried (see `## Halting`). Do not carry on by reasoning about what the skill would do.

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

## `list-agents` — `determinism-critical: false`

Answers "is this agent name loadable in this runtime right now?" — used after writing an agent
file, to tell a valid file from a loaded one.

| Runtime | Procedure |
|---|---|
| Claude Code | **No query API exists**, and the session's agent list is fixed at start-up, so a file written this turn will not appear in it. Treat the answer as *unavailable*; the first successful spawn of that agent is what confirms it. |
| agy | `manage_subagents` — read the registry and look for the name. |

**Unavailable is not "absent".** A caller must distinguish "the runtime cannot tell me" from
"the runtime says no": the first is a limitation and the run continues at a lower grade, the
second is a real finding. Reporting the first as a failure makes agent installation unusable
under Claude Code entirely, and under agy whenever the registry comes back empty — which is
observed. Callers grade the outcome (for example `verified` vs `file-only`) rather than
branching pass/fail on it.

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

### Required assertion

This rule applies to `spawn-named-checker` only; `spawn-inline-checker` and `spawn-worker` state
their own below. Because the procedures differ, parity cannot be guaranteed by construction, so a
caller checks each spawned analyzer:

1. **Spawn return — required.** The analyzer's own return must exist and parse as its named
   report (the report the caller asked for, with the keys the caller requires). A missing or
   unusable return halts: `failed: spawn-named-checker returned no usable result (<analyzer>[ <report>]: <reason>)` —
   the report name is added when one analyzer runs more than once (e.g. `SESSION_USER` / `SESSION_PROJECT`).
2. **Registry — recorded.** Under Claude Code the spawn is native and its return is the evidence;
   there is no registry to query. Under agy, read `manage_subagents` and record what it said:
   - lists the analyzer as defined and invoked → the stronger grade; continue.
   - **empty** (observed in some agy sessions), or **could not be read** → record `spawn return only (agy registry empty)`
     (or `… (agy registry unreadable)`) and continue. An empty registry says nothing either way, and halting on it would make the
     caller unusable on agy.
   - lists other subagents but **not this analyzer** → halt with the `failed:` message above
     (reason: not in agy registry). That registry is a real answer, and it says the report was
     written in-context.

The caller keeps the evidence grade per analyzer and reports it with its result. A report file
alone is **not** evidence: a main agent that skips delegation entirely and writes a well-formed
report in-context produces an indistinguishable file.

---

## `spawn-inline-checker` — `determinism-critical: true` (**divergent**)

For a checker that has **no `agents/<name>.md` file** — its prompt is supplied by the call site
rather than sourced from the harness agent directory (coherence-audit's contradiction judge,
agent-orchestrate's unattended requirement checker, and crew's review gate, whose reviewer prompt
comes from `references/experts/`). Separate from
`spawn-named-checker` because that procedure's step 1 sources a body from `../../agents/`, which
is unsatisfiable here; a skill citing the wrong one leaves the runtime to improvise, which is the
substitution these ids exist to prevent.

| Runtime | Procedure |
|---|---|
| Claude Code | `Agent(subagent_type="general-purpose")` with the inline prompt |
| agy | `define_subagent` with a role name, a description stating it is an independent judge, and the inline prompt as its body → then `invoke_subagent` |

Required assertion: where the caller has a named report file, that report must exist; where it
has none, there is no artifact clause. The evidence that the judgement came from a separate
context is **per runtime**:

| Runtime | Evidence that the judgement came from a separate context |
|---|---|
| Claude Code | The spawn is native; **its own return is the evidence**. There is no registry to query. |
| agy | The spawn's return, **plus** `manage_subagents` where it is readable. |

Under agy the registry is the stronger signal and should be checked. But it is **not** a pass/fail
bar on its own: it is observed to come back empty in some agy sessions, and a caller that fails the
whole check on an empty registry would be unable to run at all on that runtime. Record what the
registry said and let the caller decide what an absent entry means for its verdict.

---

## `spawn-worker` — `determinism-critical: true` (**divergent**)

For a subagent that **builds** — writes tests or code — from a prompt written inline at the call
site (agent-orchestrate's unattended TT writers and implementation workers cite it). Separate from
`spawn-inline-checker` because that procedure describes the subagent as an independent judge: a
builder defined under a judge's role contract is told one thing by its description and the
opposite by its prompt.

| Runtime | Procedure |
|---|---|
| Claude Code | `Agent(subagent_type="general-purpose")` with the inline prompt |
| agy | `define_subagent` with a role name, a description stating what it builds (the tests for one requirement, or one task's implementation), and the inline prompt as its body → then `invoke_subagent` |

Required assertion: where the caller names a report file, that report must exist; where it names
none, there is no artifact clause. Evidence that the work came from a separate context is **per
runtime**: under Claude Code the spawn is native and its own return is the evidence, with no
registry to query; under agy it is the spawn's return **plus** `manage_subagents` where it is
readable — the registry is the only evidence there that the work came from a separate context,
and the stronger signal, so check it. It is **not** a pass/fail bar on its own (it is observed to
come back empty in some agy sessions): record what the registry said and let the caller decide
what an absent entry means for its verdict. For a test writer that separation is the point — the
tests and the code they check must come from different contexts (maker ≠ checker).

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
| A spawned checker's return is missing or unusable, or the agy registry lists other subagents but not it (`spawn-named-checker`) | `failed: spawn-named-checker returned no usable result (<analyzer>[ <report>]: <reason>)` |

Collapsing these into one message makes every failure ambiguous — a denial reads as a missing
capability, and the fix for each is different.

---

## For skill authors

- Cite capability ids, never runtime tool names.
- Cite a **procedure id** wherever the outcome depends on exactly how the step runs.
- Declare required procedure ids in the converted-list so the sweep can assert they still appear.
- Adding a runtime means adding a column here — not editing skills.
