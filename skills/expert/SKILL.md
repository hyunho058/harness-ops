---
name: expert
argument-hint: "<role> [for <feature/context>]"
description: |
  Create and install ONE domain expert as a loadable agent in the target project's
  .claude/agents/ — defined by its output file and pass criteria, not by a persona.
  Copies a seed from references/experts/ when one exists, injects project context,
  enforces frontmatter, and verifies the file is actually loadable after writing.
  Refuses to modify an agent a human wrote; merges idempotently into one it generated.
  Use when: "/expert", "expert", "add an expert", "add a designer", "add a DB expert",
  "create an agent for", "install an expert", "전문가 추가", "에이전트 만들어줘".
  Do NOT use for: assembling a whole roster for a feature (use harness-ops:crew),
  or generating a full agent team from a design spec (that is harness-factory).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Agent
  - AskUserQuestion
---

# /expert — one expert, installed and verified

> **Runtime contract — read this first.** Before executing any step below, read
> `../../references/runtime-tools.md`. This skill names **capabilities**, not runtime tool
> names, and cites pinned **procedure ids** (`` `capability:<id>` ``) wherever the outcome
> depends on running exactly that procedure. The map turns each one into the concrete call for
> the runtime you are in. Do not substitute your own reasoning for a cited procedure id.

Create ONE expert agent and install it where the target project will actually load it.

This skill exists because writing an agent file is not the same as having an agent. This
repository contains the proof: `.claude/agents/git-analyst.md`, `git-operator.md` and
`git-pr-agent.md` are well-written, committed, and **absent from the session's agent list**
because they carry no frontmatter. A skill that writes the file and reports success would
have reported success on all three.

---

## Core Rules

1. **An expert is an output file plus a pass criterion** — never a persona. "You are a
   designer" produces designer-sounding prose and a review that ends in "looks good". The
   next stage needs a named file and a bar that can be checked by reading it.
2. **Seed first, author second** — if `references/experts/<role>.md` exists, copy it and
   inject context. Authoring from scratch in a bare project is why quality drifts run to
   run.
3. **Frontmatter is the deliverable** — a file without valid `name` / `description` /
   `tools` is not an expert, it is a text file. Verify after writing (§4).
4. **Never write into the plugin's own install directory** — a marketplace update
   overwrites it. See §5.
5. **Never modify a file a human wrote** — provenance decides, not guesswork (§6).
6. **Ask before writing, unless a human already approved this exact write** (§7).

---

## Inputs

| Input | Form | Meaning |
|-------|------|---------|
| role | kebab string | The capability: `designer`, `db-expert`, … Becomes the agent `name`. |
| context | free text or path | What this expert is for. A caller passes `brief: <path>` to inject stack / UI / test-runner facts. |
| `output:` | repo-relative path | The file this expert must produce. Required — see Rule 1. |
| `pass_criteria:` | text | The bar that output must clear. Required. |
| `approved_by:` | path to a ledger | **Optional.** A caller that already obtained the human's approval for this write passes the ledger path; §7 then skips its own prompt. Absent → prompt. |

If `output` or `pass_criteria` is missing and the invocation is interactive, ask for them.
Do not invent them: an expert with an invented bar passes its own review by construction.

---

## 1. Resolve the seed  (R5.1, R5.2)

Find `../../references/experts/<role>.md` with `capability:read-file` — the plugin-root
`references/`, which is
this repository's convention for documents shared between skills (see
`skills/coherence-audit/SKILL.md:32`). Seeds live there rather than under this skill
because `crew` reads one of them too.

- **Found** → read it. It is the body. Substitute every `{{placeholder}}` the seed declares
  in its own `SEED CONTRACT` comment — that comment, not this list, is the authoritative set
  of placeholders for that seed — and
  **remove the trailing `SEED CONTRACT` comment** — it documents the placeholders for this
  skill and has no place in an installed agent. A leftover `{{placeholder}}` is a defect:
  fail rather than install a file that instructs an agent to read `{{brief_path}}`. Do
  **not** rewrite the seed's structure or its pass criteria — the seed exists so the same
  role behaves the same way in an empty project as in a mature one.
- **Not found** → author the body, and it MUST contain the output file and the pass
  criteria (Rule 1).

Seeds are **read-only**. Never write back into `../../references/experts/`, and never
install a seed that is marked as a gate component rather than a roster expert —
`cross-functional-reviewer.md` says so in its own header and is run by `crew` as a
headless prompt, not installed here (D43).

---

## 2. Choose the install path  (D8, R5.10)

| Situation | Install to |
|-----------|-----------|
| Normal target project | `<project>/.claude/agents/<role>.md` |
| CWD is a plugin source tree | `<project>/.claude/agents/<role>.md` — the local harness, **never** the distributed `agents/` directory |

**Detect a plugin source tree** before writing: `.claude-plugin/plugin.json` exists at
CWD, or the marketplace `source` resolves to this directory. In this repository
`plugins/harness-ops` is a symlink to `../`, so the repo root *is* the plugin directory —
writing to `agents/` there would ship an expert to every installation of the plugin.

The plugin's **installed** directory (`~/.claude/plugins/**`) is never a write target
under any circumstance: a marketplace update overwrites it without warning.

Promotion to `~/.claude/agents/` is a **manual** decision a human makes after the expert
has proven itself in more than one project. This skill does not promote.

If `.claude/agents/` does not exist, creating it is part of the write — fold it into the
§7 confirmation rather than asking separately.

---

## 3. Write the file  (R5.3)

```markdown
---
name: designer
description: Produces specs/<feature>/design.md — screen-by-screen states and responsive
  behaviour. Use when a feature has a user-facing surface.
tools: Read, Grep, Glob, Write
generated-by: harness-ops:expert
generated-at: 2026-09-21T14:02:11+09:00
---

# designer

## Output
`specs/alarm-center/design.md` — this file, and only this file.

## Pass criteria
- Every screen defines default / empty / loading / error states.
- Every screen states its responsive breakpoint behaviour.
...
```

Write it with `capability:write-file`.

`name`, `description` and `tools` are **required**. `generated-by` is the provenance
marker §6 depends on — omitting it makes the file indistinguishable from one a human
wrote, and the next run will refuse to touch it.

Give `tools` the minimum the role needs. A reviewer role gets read tools only; it must not
be able to edit what it reviews.

---

## 4. Verify it loads — two steps  (R5.4, R5.11, D41)

Writing is not the end of the task.

**Step ① — parse the frontmatter.** It must be valid YAML and must carry `name`,
`description` and `tools`. **Failure here is a hard failure**: revert the write and report
it. This is the check that catches this repository's real failure mode.

**Step ② — query the runtime** with `capability:list-agents`.

- Name found → record `load_check: verified`.
- Name not found, or the query is unavailable → record `load_check: file-only` and
  **continue**.

**`file-only` is not a failure.** Under Claude Code there is no declared agent-list query
API and the list is fixed at session start, so a file written this turn legitimately will
not appear; under `agy` the subagent registry is commonly empty. A file that passed step ①
but is not visible is a runtime limitation, not a defective file — reporting it as a
failure would make the skill unusable on whole runtimes and would be a false negative of
exactly the kind honest degradation is supposed to avoid.

`file-only` is upgraded to `verified` the first time that expert is actually spawned and
the call returns — under Claude Code the native spawn's own return is the evidence
(`skills/check-harness/SKILL.md:176-178`).

Report the grade. Never report `verified` without having observed the name.

---

## 5. Name collision  (R5.5, D9c)

Before writing, use `capability:list-paths` to check whether `<role>.md` already exists at the
install path, and check
whether the name collides with an existing skill or agent elsewhere in the project. A
collision that is not a same-role re-run is a stop, not a rename.

---

## 6. Existing file: provenance decides  (D34, R5.5, R5.6)

Two rules used to collide here — "never overwrite" and "merge idempotently" — because both
describe the same state. Provenance separates them mechanically:

| Target file | Has `generated-by: harness-ops:expert`? | Action |
|-------------|----------------------------------------|--------|
| exists | **yes** | Merge per §6.1. |
| exists | **no** | **A human wrote this. Stop and escalate. Do not edit it.** |
| absent | — | Write it. |

The second row is the mechanical enforcement of the inherited boundary "do not delete or
overwrite work you did not create".

### 6.1 Idempotent merge rules — inlined on purpose  (D10, R5.7)

These three rules are written out **here**, in this skill's body. They are not read from
anywhere at runtime.

> **Provenance.** The rules originate in harness-factory's `team-build`
> (`skills/team-build/SKILL.md`, §"idempotent merge"). That original lives only in a
> **version-pinned local plugin cache**, which a globally-distributed skill cannot assume
> exists on another machine — and this project deliberately does not depend on
> harness-factory. The citation is attribution, not a runtime path.

1. **Merge by section, not by file.** Replace only the sections this run derives
   (`## Output`, `## Pass criteria`, and the frontmatter fields it owns). Leave every
   other section byte-identical.
2. **Preserve human edits.** Prose a human added inside a section this run does not own
   is kept. Re-running must not undo someone's refinement — an expert that resets on every
   run teaches people not to edit it.
3. **Never delete what is only on disk.** A section present in the file but absent from
   what this run derives is **kept and reported as a warning**. Silent deletion of
   unrecognised content is how a merge destroys work; a warning gives the human the
   decision.

Re-running with the same inputs after a merge must produce no further change. That is the
idempotency this section is named for, and it is the test for it.

---

## 7. Confirm before writing  (D9d, R5.8, R5.9)

The file lands in the project, is committed, and propagates to the team. Confirm first.

| Invocation | Confirmation |
|------------|--------------|
| Standalone (a human called `/expert`) | **Ask** via `capability:ask-user`. Show the install path, the frontmatter, the output file, and the pass criteria. Include directory creation in the same question. |
| Called with `approved_by: <ledger path>` | **Skip** — but first verify that the ledger actually records a human approval covering expert file writes. If it does not, ask. |

The skip exists only because the caller's single approval prompt already absorbed this
question. It is not a general-purpose bypass: a standalone call keeps the confirmation,
so an optimisation made for one caller does not remove the safety of the other.

Never ask per-file when installing several experts for one caller — that caller batches
them into one write point precisely so the human is asked once.

---

## Checklist Before Stopping

- [ ] `output` and `pass_criteria` are present and were not invented
- [ ] Seed used if one existed; not rewritten
- [ ] Install path is the project's `.claude/agents/`, never a plugin install directory
- [ ] Frontmatter carries `name`, `description`, `tools`, `generated-by`
- [ ] Step ① frontmatter parse passed (a failure reverted the write)
- [ ] Step ② runtime query attempted; `load_check` recorded as `verified` or `file-only`
- [ ] Existing file handled by provenance: merged if generated, stopped if human-written
- [ ] Merge left unrecognised sections in place and warned about them
- [ ] Human confirmed the write, or a verified approval record covered it
- [ ] Reported the install path and the `load_check` grade — no unverified success claim
