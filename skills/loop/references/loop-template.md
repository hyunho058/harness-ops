# loop.md — Loop Contract

> The supervisor document for `<task / feature>`. Defines what "done" means so
> the loop can verify itself instead of asking a human every step. Copy this,
> fill the brackets, get it approved, then run `/harness-ops:loop`.

## Goal
<one sentence: what this loop must achieve, and the spec/PRD it must not violate>

## Scope & non-goals
- In: <what the loop may change>
- Out: <what it must not touch>

---

## Gate 1 — Pass/Fail  (100% required, binary)
Each line is a command; a non-zero exit fails the gate.

| Check | Command |
|-------|---------|
| build | `<e.g. npm run build>` |
| typecheck | `<e.g. npm run typecheck / tsc --noEmit>` |
| lint | `<e.g. npm run lint>` |
| tests | `<e.g. npm test>` |

> If a check has no command in this project, write `N/A — <reason>`. Do not skip silently.

## Gate 2 — Quantitative  (measured vs threshold)

| Metric | Threshold | How measured |
|--------|-----------|--------------|
| test coverage | `≥ <N>%` | `<command>` |
| p95 latency | `≤ <N> ms` | `<how>` |
| error-log rate | `≤ <N>` | `<how>` |
| `<other>` | `<threshold>` | `<how>` |

## Gate 3 — Qualitative  (score + grounds + action)
Score each /10. A score alone is invalid — grounds and action are mandatory.

- **Architecture fit** — does the change match the existing design?
- **Naming / readability** — clear at the call site?
- **User-flow naturalness** — does the path feel right end to end?
- **Spec alignment** — consistent with the original intent?

```
<item>: <score>/10
  grounds: <specific, checkable observation>
  action: <change that raises it | "none — meets bar" + why>
```

---

## Autonomy Boundary

**✅ Auto-fix (stay in the loop):** lint/type/format, missing in-scope tests,
docs/comments, local renames, behaviour-preserving refactors.

**🛑 STOP — call a human (escalate):**
- DB schema changes
- Data-loss-capable migrations
- Auth / permission / access-control policy changes
- Payment / security-sensitive changes (secrets, crypto, billing)
- Anything conflicting with this contract's Goal or the spec/PRD

## Exit criteria
The loop exits only when **every** gate above passes and the Evidence Report is
emitted. Hitting a 🛑 boundary ends the loop in escalation, not completion.
