# Converted skills — the portability contract's enforcement list

A skill appears here **only after it already passes** `scripts/portability-lint.sh`.
Listing is the act of declaring a skill ported; it is not a to-do marker.

The linter and the sweep both read this file:

- **Unlisted skills are not checked at all.** Rollout is incremental, so an unconverted skill must
  not fail the gate.
- **Listed skills are checked strictly**, including that every id in `required-procedure-ids` still
  appears in the skill body. That column is what catches a determinism-critical step quietly
  rewritten back into prose — the linter can verify a cited id *exists*, but only this column
  notices one that went missing.

**Ordering rule:** finish the conversion, verify it passes, *then* add the row. Adding a row first
makes the blocking hook deny every intermediate save of the rewrite.

<!-- The table below is parsed. Columns: skill | required-procedure-ids (comma-separated, or "-") -->

| skill | required-procedure-ids |
|---|---|
| coherence-audit | resolve-harness-root, run-glob-overlap, read-declared-surface-schema, spawn-inline-checker |
| check-harness | spawn-named-checker |

Listing `check-harness` also brings `agents/*.md` into lint scope, because its
`spawn-named-checker` procedure feeds those bodies to the runtime as prompt text.

## Repo facts this work established (recorded here because `specs/` is gitignored)

- **`.gemini/skills/` is a symlink farm, not a copy.** Each entry symlinks into `skills/`. It was
  previously believed to be a frozen duplicate of 7 skills; it is not. Two links
  (`deep-interview`, `doc-drift`) pointed at skills that no longer exist and were removed; the
  5 valid links remain. Antigravity does not read workspace `.gemini/skills/` at all — discovery
  is global-only — so the directory is inert either way.
- **Antigravity discovery is global.** Skills are registered via `~/.gemini/config/skills.json`
  by absolute path. A git worktree's copies are therefore invisible until that path is repointed,
  which is what `scripts/pilot-verify.sh` does (and unconditionally restores).
- **`agy -p` auto-denies `run_command`.** Headless mode cannot prompt, so a scoped
  `permissions.allow` entry is not enough — a skill needs the capability before it reaches any
  pinned script. `pilot-verify.sh` uses `--dangerously-skip-permissions` for its time-boxed
  verification run instead; see that script's header for the reasoning.

## Not yet converted (11)

`agent-orchestrate`, `autopilot`, `build-order`, `context-audit`, `decompose`, `loop`, `qa`,
`requirements-interview`, `scaffold`, `specify`, `worktree`

These are untouched by the gate until they are converted and listed.
