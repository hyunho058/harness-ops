# review-schema.md — the crew review artifact contract

> One review produces one JSON file. It carries a verdict, the findings, and — the part
> that is easy to omit and fatal to omit — **evidence that the review was actually
> delegated**. Artifact existence alone proves nothing: an orchestrator that skipped
> delegation and wrote a well-formed report from its own context produces a file
> indistinguishable from the delegated one (`skills/check-harness/SKILL.md:180-190`).
> The `evidence` field is the only thing that tells them apart.
> **This doc defines DATA + field semantics only.** How the gate is run, how findings feed
> rework, and the anti-spin rule live in `crew`'s SKILL.md.

Four sub-contracts:
1. **File naming** — target and iteration in the name (§1 — R6.10).
2. **Top-level fields** — verdict, reviewer, isolation (§2 — D27).
3. **Evidence** — required on both the headless and the degraded path (§3 — D25, R6.2, R6.3).
4. **Findings** — the flag-only payload (§4 — D27, R6.6, R6.7).

---

## 1. File naming  (R6.10)

```
specs/<feature>/review-<target>-<iteration>.json
```

**The caller writes this file, not the reviewer.** The reviewer returns the JSON object as
its entire output and is granted no write tool
(`references/experts/cross-functional-reviewer.md` › Required tools). On the isolated-process
path that output is stdout, which the caller is already redirecting to a file for evidence
(§3); on the degraded path it is the spawn's return value. Either way the caller parses that
output, validates the **reviewer-owned subset** of §2, adds the caller-owned fields, and
writes the result to the path below. Validating it against the whole of §2 would reject a
correctly-behaving reviewer, because two of those fields describe how the reviewer was run —
something it cannot observe about itself.

Flag-only is mechanical only on the isolated-process path, where the tool restriction is part
of the invocation. On the degraded path the spawned checker holds write tools, so the caller
verifies after the fact that the target file was not modified (`review-gate.md` §4).

- `<target>` — what was reviewed: `spec`, `design`, …
- `<iteration>` — 1-based, incrementing per re-review of the same target.

```
review-spec-1.json      review-spec-2.json      review-design-1.json
```

The target must be in the name because two consumers branch on it: the rework router
(a `spec` finding and a `design` finding have different owners — D40) and the commit set
(which enumerates artifacts by declared output — D21).

---

## 2. Top-level fields  (D27)

```json
{
  "verdict": "BLOCK",
  "target": "specs/alarm-center/design.md",
  "reviewer": "cross-functional-reviewer",
  "iteration": 1,
  "isolation": "headless",
  "evidence": { },
  "findings": [ ]
}
```

| Field | Values | Meaning |
|-------|--------|---------|
| `verdict` | `BLOCK` \| `WARN` \| `OK` | The three-way verdict reused from `coherence-audit`, so callers branch the same way across skills. **Any** `BLOCK` finding makes the verdict `BLOCK`. |
| `target` | repo-relative path | The file reviewed. Routes rework (§4). |
| `reviewer` | role name | Which reviewer produced this. The cross-functional reviewer is a gate component, never a roster role (`roster-schema.md` §1). |
| `iteration` | integer ≥ 1 | Matches the filename. |
| `isolation` | `headless` \| `subagent-degraded` | How separated the reviewer was from the orchestrator. See §3. |

**Ownership.** `verdict`, `target`, `reviewer`, `iteration` and `findings` are
**reviewer-owned** — the reviewer returns exactly these as its output. `isolation` and `evidence`
are **caller-owned**: they describe how the reviewer was invoked, which the reviewer cannot
observe about itself, and letting it assert them would make the evidence rule self-reported
and therefore worthless (§3). The caller merges the two halves into the stored artifact.

### Gate semantics

`BLOCK` present → the next stage does not start; rework is triggered (R6.5). `WARN` is
recorded and does not block. `OK` passes the gate.

**Flag-only.** The reviewer records findings; it never edits the file it reviewed
(R6.6). A reviewer that fixes what it finds is no longer a checker.

---

## 3. Evidence — required, on both paths  (D25, R6.2, R6.3)

A review with no evidence is **invalid**, not merely weak: it is discarded and the gate
is treated as not run.

### Headless path

```json
"evidence": {
  "mode": "headless",
  "command": "claude -p ... ",
  "exit_code": 0,
  "stdout_path": "_workspace/review-design-1.out",
  "stderr_path": "_workspace/review-design-1.err"
}
```

Capture the exit code by **redirecting to files with no pipe** and reading `$?`
immediately after. Do not use `${PIPESTATUS[0]}`: that array is bash-only and zsh spells
it `$pipestatus`, so on a zsh login shell it silently yields an empty value that is
indistinguishable from "no evidence". Removing the pipe is shell-independent and also
removes the `| head -N || true` idiom's habit of swallowing the exit code — the form used
at `scripts/pilot-verify.sh:192, 199, 207` discards it, so copying that shape verbatim
leaves no evidence at all.

### Degraded path — the same bar (R6.3)

```json
"evidence": {
  "mode": "subagent-degraded",
  "reason": "headless spawn failed: command not found",
  "agent_return": "<the Agent call's own return>"
}
```

When headless startup fails, the review degrades to a subagent rather than stopping — a
global skill meets missing binaries, denied permissions and auto-denied tools often enough
that halting would make whole environments unusable (D18). But the degraded path must
carry **equivalent evidence**: the `Agent` call's own return, which under Claude Code is
the native spawn's evidence (`skills/check-harness/SKILL.md:176-178`).

Without this requirement the evidence rule is trivially bypassed — "headless genuinely
failed" and "the orchestrator skipped delegation and wrote the file itself" produce the
same artifact. If `agent_return` is absent, this is **not** a degradation but a
**non-delegation**: park the stage.

The chosen `isolation` value and its reason are also mirrored into `pipeline.md` §5, so
the ledger alone shows how well-evidenced the run is.

---

## 4. Findings  (D27, R6.6, R6.7)

```json
"findings": [
  {
    "severity": "BLOCK",
    "target": "specs/alarm-center/design.md#검색-결과",
    "claim": "The results screen defines no empty state.",
    "required_change": "Add an empty state: copy, illustration slot, and the action that leaves it."
  }
]
```

| Field | Form | Meaning |
|-------|------|---------|
| `severity` | `BLOCK` \| `WARN` | `BLOCK` fails the gate. |
| `target` | path, optionally `#section` | **Where.** A finding whose target is a different file than the review's `target` is what routes post-approval rework: a design review finding that points at `spec.md` parks the design stage rather than editing an approved spec (R6.9). |
| `claim` | one sentence | **What is wrong.** A statement of fact about the file, not an impression. |
| `required_change` | one sentence | **What would resolve it.** A finding the author cannot act on produces the endless "still ambiguous" ping-pong that anti-spin exists to stop. |

### Findings are the rework input (R6.7)

When a gate blocks, the rework call names this file by path in its args and states that
these findings must be resolved. The findings do not get summarised into prose on the way
— a paraphrase is the orchestrator's own reasoning re-entering a checker's output, which
is the separation the gate exists to maintain.

### Anti-spin (R6.8)

Re-review increments `iteration`. If an iteration flips no finding from fail to pass,
stop and escalate rather than starting another one (`skills/loop/SKILL.md:275`). Document
review is unusually prone to a stable disagreement that looks like progress.
