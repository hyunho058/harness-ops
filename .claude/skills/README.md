# `.claude/skills/` — what the files here are, and what they are not

Two different kinds of entry live in this directory, and only one of them is a skill.

## `git-commit/SKILL.md` — a real, loaded skill

Claude Code discovers a project skill at **`.claude/skills/<name>/SKILL.md`** — a directory whose
name is the skill name, containing `SKILL.md`. `git-commit` is in that form, so it loads, and a
session lists it as bare `git-commit`.

## `<name>.md` — frontmatter-parity stubs, not entry points

Every other entry is a flat symlink such as `worktree.md -> ../../skills/worktree/SKILL.md`. These
are **not loaded as skills**: the flat spelling is not a location Claude Code looks in. Nothing
here makes `/worktree` exist.

What they are is the parity convention the `PostToolUse` hook
`.claude/hooks/check-stub-sync.sh` warns about — a stub per skill so `.claude/skills/` mirrors
`skills/`, and the frontmatter can be read from one place. That is a documentation habit, not a
registration mechanism. Do not add one expecting a new command to appear.

**Where the skills actually come from.** `skills/<name>/SKILL.md` reaches a session through the
installed **plugin**, namespaced: `harness-ops:worktree`, `harness-ops:qa`, `harness-ops:loop`.
That is the entry point to cite in documentation.

## Why these are not simply converted to directory form

Converting `worktree.md` to `.claude/skills/worktree/SKILL.md` would make it load — and the same
skill would then exist twice in one session, once bare and once as `harness-ops:worktree`, from the
same source file. Duplicate skill names are exactly what this repo's own
`skill-portfolio-analyzer` flags as a collision, so the parity stub stays a stub deliberately. If a
skill genuinely needs a project-local entry point that the plugin does not provide, give it the
directory form the way `git-commit` has it, and accept that it is a distinct skill.

## Dangling stubs are a defect

A stub pointing at a deleted skill is dead weight that reads as a working link. `deep-interview.md`
and `doc-drift.md` were both dangling and have been removed; `references/converted-skills.md`
records the same two being cleared out of `.gemini/skills/` earlier. Check with:

```bash
for f in .claude/skills/*.md; do [ -e "$f" ] || echo "DANGLING: $f"; done
```
