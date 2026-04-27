---
name: doc-drift
argument-hint: ""
context: fork
description: |
  Use this skill when the user wants to audit the memory and documents Claude
  Code loads into context — CLAUDE.md (user global + project + nested),
  MEMORY.md, @imports, .claude/skills, .claude/agents, .claude/commands,
  installed plugins — and detect three kinds of issues: outdated claims,
  mutually contradictory statements, and risky-or-ambiguous wording. Produces
  a prioritized improvement list at `.drift-reports/`. Zero config.
  Trigger phrases: "doc drift", "memory drift", "memory audit", "context drift",
  "docs audit", "document review", "document audit", "memory check",
  "outdated docs", "document conflict".
---

# doc-drift — Claude memory audit

One sentence: **Scan all memory and documents Claude loads in this project, find anything outdated, contradictory, or risky/ambiguous, and surface them in priority order.**

## 3 Stages

### 1. Collect what's loaded

Collect all files that Claude Code can actually load or reference in this project context. LLM finds them directly via `Read` / `Glob` / `Grep` — no scripts.

**Starting points**
- `~/.claude/CLAUDE.md` (if exists)
- `<cwd>/CLAUDE.md` + nested `**/CLAUDE.md`
- `~/.claude/projects/<encoded-cwd>/memory/MEMORY.md`
  - Encoding: replace `/` in the absolute cwd path with `-`. e.g. `/foo/bar` → `-foo-bar`
- `<cwd>/.claude/skills/**/SKILL.md`
- `<cwd>/.claude/agents/*.md`
- `<cwd>/.claude/commands/*.md`
- `~/.claude/plugins/**` (skills/agents/commands from installed plugins)

**Expansion**
From each file, extract and recursively follow:
- `@import` tokens (resolve relative to `~/.claude/` for user global files, otherwise relative to the file's directory or project root)
- Relative markdown links `[text](./path.md)`
- File path mentions inside backticks (only if the path actually exists)

Collect until no new nodes are found.

### 2. Detect three types of issues

LLM reads each audited file and looks for **only these three**:

| Type | Criterion |
|------|-----------|
| **Outdated** | Claims that don't match the current reality of code/config (paths, commands, numbers, policies, versions, etc.) |
| **Conflict** | Two documents describing the same topic differently |
| **Risky / Ambiguous** | Instructions that could be interpreted differently or are dangerous if followed incorrectly (e.g., "do it appropriately", "depending on the case", delete/override instructions without explicit conditions) |

Every finding must include **evidence**: the claimed location (`file:line`) and the counter-evidence (`file:line` or current code quote).

If confidence is low, omit the finding entirely. False positives are this tool's biggest enemy.

### 3. Prioritized improvement suggestions

Sort findings by the following criteria and write the report:

1. **Impact scope** — Files loaded every conversation (`CLAUDE.md` / `MEMORY.md` etc.) go to the top
2. **Severity** — Things that break if wrong instructions are followed (HIGH), confusing but easy to recover (MED), minor discrepancies (LOW)
3. **Fix difficulty** — Clear fix suggestions go first

Include a **suggested fix** for each finding — specific enough for a human to approve with a simple "OK/NO".

## Output

Save to `.drift-reports/` directory (create if missing; do NOT add to `.gitignore` — history must be visible in PRs):

- `.drift-reports/<YYYY-MM-DD-HHMM>.md` — timestamped report
- `.drift-reports/latest.md` — copy of the latest report

**Report template:**

```markdown
# Memory Audit — {timestamp}

**Scanned:** {n} files reachable from CLAUDE.md / MEMORY.md / skills / agents
**Findings:** HIGH {h} / MED {m} / LOW {l}

## Top priority
1. **[HIGH] `path:line`** — {one-line summary}
   - Claim: "..."
   - Reality: `other/path:line` — ...
   - Suggestion: ...
2. ...

## Medium
...

## Low
...

## Pending judgment (human decision needed)
- Conflicts where it's unclear which side is correct
- Ambiguous items where the intent is uncertain

## Next steps
Create an auto-fix PR? (Only for Outdated findings with a clear fix)
```

## Auto-fix (optional)

Ask only after presenting the report summary:

> "Found HIGH {h} findings. What would you like to do?
> 1) Create PR with clear fixes only
> 2) Report only"

If chosen: create atomic commits per finding on a `docs/drift-fix-<timestamp>` branch, then `gh pr create`.

**Always exclude**: Conflicts (requires human judgment on which side is correct), Risky/Ambiguous (requires intent verification).

## Principles

- **Minimize false positives** — When in doubt, leave it out. The tool's value depends on humans trusting the report.
- **Evidence required** — Every finding must cite both sides as `file:line`.
- **Respect the summary + link pattern** — `CLAUDE.md` summarizing or linking other docs is normal. Only flag when meaning has actually drifted.
- **Files loaded every conversation take priority** — Drift in `CLAUDE.md` and `MEMORY.md` is more dangerous than any other file.

## Arguments

| Input | Behavior |
|-------|----------|
| `/doc-drift` | Full audit (default) |
| `/doc-drift recent` / `recent 50` | Only areas changed in the last N commits |
| `/doc-drift path <glob>` | Specific paths only |
