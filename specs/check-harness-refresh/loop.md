# loop.md — Loop Contract

> The supervisor document for `check-harness-refresh` (verification gate after
> agent-orchestrate's Parallel Subagent execution). Implementation is already
> complete: iteration 1 starts at VERIFY.

## Goal
Every Requirement in `specs/check-harness-refresh/spec.md` (R0–R10, 70 GWTs) holds in the working tree, without violating its Decisions or Constraints.

## Scope & non-goals
- In: the files the spec's tasks name (skills/check-harness/**, agents/*.md, references/runtime-tools.md, references/converted-skills.md, skills/coherence-audit/scripts/run-tests.sh, Makefile, README.md, skills/expert/SKILL.md, skills/crew/references/review-schema.md).
- Out: any test file listed in `specs/check-harness-refresh/gwt-tests.md` (never modified); `.claude/skills/check-harness.md` (symlink, never edited); `hooks/hooks.json`, `plugins/` paths; `.gemini/` tomls (spec Non-goal); git commits / pushes.

---

## Gate 1 — Pass/Fail  (100% required, binary)

| Check | Command |
|-------|---------|
| build | N/A — no build step (markdown skills + stdlib Python scripts) |
| typecheck | `python3 -m py_compile` is covered by the tests importing every script; N/A as a separate step |
| lint | `scripts/portability-lint.sh --sweep` |
| tests | `make test` (run-tests.sh A–E incl. the 9 `tt*_test.sh` acceptance files, plus `scripts/test-block-main-push.sh`) |
| acceptance tests unmodified | every `skills/check-harness/tests/tt*_test.sh` sha256 appears in `specs/check-harness-refresh/gwt-tests.md` |
| no line-number citations (R0.4) | `grep -rn 'check-harness/SKILL.md:[0-9]' skills agents references README.md \| grep -v '^skills/check-harness/'` prints nothing |
| stub still a symlink (R10.4) | `test -L .claude/skills/check-harness.md` |
| evals parse (R10.3) | `python3 -c "import json;json.load(open('skills/check-harness/evals/evals.json'))"` |
| HTML placeholder parity | the set of `{{TOKEN}}`s in `references/html-template.html` equals the set named in SKILL.md |
| no stray bytecode (D2) | `find . -name __pycache__ -not -path './plugins/*'` prints nothing |

## Gate 2 — Quantitative  (measured vs threshold)

| Metric | Threshold | How measured |
|--------|-----------|--------------|
| run-tests.sh failures | `= 0` (of ≥ 106) | `make test` summary |
| block-main-push failures | `= 0` (of 53) | `make test` summary |
| item-count statements ≠ 26 | `= 0` | grep "items"/"-item" counts in SKILL.md, checklist.md, html-template.html, README.md |
| checklist rows by level | `L1 9 / L2 10 / L3 7` (26) | count the `| L1 |`/`| L2 |`/`| L3 |` cells in checklist.md's item tables |
| acceptance-test files passing | `9 / 9` | section E of `make test` |

## Gate 3 — Qualitative  (score + grounds + action; checker-scored)

- **R7 orchestration** — SKILL.md Phase 0/1/Delegation assertion meet R7.1–R7.8.
- **R8 analyzers** — the four agents meet R8.1–R8.5 and D10's key lists.
- **R9 scoring** — checklist.md + SKILL.md Phase 2/3 meet R9.1–R9.6 and D15–D18, D22.
- **R10 docs** — citations, converted-skills row, evals, README meet R10.1–R10.4.
- **Spec alignment** — no file contradicts a Decision/Constraint or builds a Non-goal; the execution-time amendments in D5/D10 are reflected consistently.

```
<item>: <score>/10
  grounds: <specific, checkable observation>
  action: <change that raises it | "none — meets bar" + why>
```
Pass bar: every item ≥ 8/10 with grounds.

---

## Autonomy Boundary

**✅ Auto-fix (stay in the loop):** lint/format, doc/comment/wording fixes in skill and agent markdown, local renames, behaviour-preserving script fixes that keep Gate 1 green.

**🛑 STOP — call a human (escalate):**
- DB schema changes
- Data-loss-capable migrations
- Auth / permission / access-control policy changes
- Payment / security-sensitive changes (secrets, crypto, billing)
- Anything conflicting with the spec's Goal, Decisions or Constraints
- Any change that would require editing a test file listed in gwt-tests.md

## Exit criteria
The loop exits only when **every** gate above passes and the Evidence Report is
emitted. Hitting a 🛑 boundary ends the loop in escalation, not completion.

---

## Lessons  (self-learning — carried across runs of THIS contract)
