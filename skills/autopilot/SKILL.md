---
name: autopilot
argument-hint: "[start <build_order path> | status | stop]"
description: |
  Keep a build-order (②) run going UNATTENDED overnight — safely. A thin
  safety-governor + scheduler: it re-invokes build-order on a schedule (a
  ScheduleWakeup primary cadence paired with a durable cron backstop), ONE unit per
  tick, reading durable state from disk each time, and enforces six hard limits
  (wall-clock, max-tick, consecutive-park, per-tick-timeout, crash-loop, kill-switch)
  that HALT the run safely. It NEVER drives a live session — no tmux keystrokes, no
  /compact injection; the durable ledgers of ①/② make a stateless fresh-tick model
  possible. Judgment = 0: it only schedules ticks and enforces limits; it decides
  nothing about the work and reuses build-order/loop for everything.
  Use when: "/autopilot", "run the build overnight", "keep ticking unattended",
  "night run", "drive build-order unattended", "overnight build governor",
  "schedule the build run".
  Do NOT trigger for: a single feature (use /harness-ops:loop) or planning/driving
  features once (use /harness-ops:build-order). autopilot only governs an UNATTENDED
  multi-tick run of an already-approved build_order.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
  - Skill
  - ScheduleWakeup
  - CronCreate
  - CronDelete
  - CronList
  - PushNotification
---

# /autopilot — Unattended Overnight Run Governor

Keep an **already-approved** build-order (②) ticking overnight, unattended, **safely** — and stop
the moment anything looks wrong.

`autopilot` does **not** do the work and does **not** judge it. It is a **governor**: it schedules
ticks, enforces six hard limits, and relays escalations. Every unit of real work happens inside ②
(which drives ①'s loop); `autopilot` only decides *when the next tick fires* and *whether the run
should keep going at all*.

The whole point is to run for **hours unattended** — surviving the context compactions and even a
session death that a long run hits — **without ever driving a live session**. There is no live
session to babysit: each tick reads durable state from disk, does one unit, and exits. That is what
makes "12h unattended" safe and what honors the rule **never send keystrokes into a live session**.

---

## The model: scheduled fresh-tick (NOT a live-session babysitter)

```
ScheduleWakeup (primary, in-session, fast cadence) ─┐
                                                     ├─► a TICK:  read disk → 1 ② unit → exit
durable CronCreate (backstop, cross-session, sparse)─┘            (no /compact, no tmux, no keystrokes)
```

- A tick is `Skill(harness-ops:build-order, args="resume mode: unattended")` — ② reads
  `build_order.md` / `progress.md`, does the next unit, exits.
- The **primary** cadence (`ScheduleWakeup`) is the normal heartbeat; it dies if the session dies.
- The **backstop** (`CronCreate` with `durable: true`) is sparse and **survives a session death** —
  it resurrects a hung/dead run *within a live REPL* (see the resurrection bound in the Rules).
- Because all state is on disk, a compact (same session) or a death (new session) is survived
  identically: the next tick just re-reads the ledgers. This is the OUTER analogue of ①'s
  `progress.md` and ②'s `build_order.md`.

---

## The durable run-control ledger (`autopilot.md`)

`autopilot`'s own state must outlive every tick (each tick is a fresh context that forgot the last
one's counters), so it lives in a durable `autopilot.md`, written **atomically (temp + rename)**. It
is the governor's source of truth — never ephemeral `TaskCreate`.

```
# autopilot.md — <run name>
## Config  (human-approved before the run; see Phase: Approve)
- build_order: <path to the ② build_order.md this run drives>
- cadence_seconds: <primary ScheduleWakeup delay; MUST be < per_tick_timeout>
- per_tick_timeout_seconds: <upper bound on a single ② unit>   # default 900 (15m)
- wall_clock_cap_hours: 12
- max_ticks: 200                     # also the cost cap (no token meter exists)
- consecutive_park_cap: 3
- crash_loop: { max: 3, window_minutes: 10 }
- killswitch_path: <runDir>/STOP

## State  (counters — the durable authority for halting)
- status: running | halted | done
- halt_reason: <text when halted>
- run_started_at: <ts>
- tick_count: <n>                    # incremented + flushed at tick ENTRY
- last_tick_started_at: <ts>
- lease_renewed_at: <ts>             # in-flight if fresh; stale-past-timeout ⇒ hung
- last_tick_completed_at: <ts>
- consecutive_parks: <n>
- recent_crashes: [<ts>, ...]        # for the M-in-N window
- backstop_cron_id: <id>             # so halt can CronDelete it
```

The single-flight **lock is NOT a field here** — a ledger field would re-introduce a read-check-write
race. The lock is a separate atomic lockfile/dir (below).

---

## Single-flight lock (a true mutex — both acquire and reclaim are atomic)

The primary and the backstop can fire near-simultaneously; two concurrent ticks driving the same
`build_order.md`/`progress.md` would corrupt the ledgers the whole stack resumes from. So a tick must
hold an exclusive lock, acquired with an **atomic create-or-fail** primitive (never read-then-write):

- **Acquire:** `mkdir <runDir>/.tick.lock` (atomic; the loser gets `EEXIST` and exits) — or an
  `O_EXCL` / symlink create. The acquisition *itself* is the test-and-set; the loser does not run.
- **Lease:** the holder writes its id + timestamp into the lockdir and renews `lease_renewed_at` at
  each governor boundary. The lock is reclaimable only when the lease is **stale past
  `per_tick_timeout`** (which is why a *slow* unit under the timeout is never mistaken for *hung*).
- **Reclaim (also atomic):** a reclaimer claims a stale lock by `rename` /
  `mv .tick.lock .tick.lock.<reclaimer-id>` — only one rename of that inode wins; a second reclaimer's
  rename fails (`ENOENT`) and exits. **Never `rmdir`+`mkdir`** (a two-step steal that lets two
  reclaimers both run). The winner recreates the lock and removes its `.tick.lock.<id>` marker.
- **Release:** the holder removes the lockdir on tick completion.

---

## Phase: Start — config + human approval

Invoked as `/autopilot start <build_order path>`. An unattended run never starts on an unapproved
config — the human owns the limits, up front.

### 1. Build the config
Start from the defaults (`references/autopilot-template.md`) and fill: the `build_order` to drive,
the six limits, and the primary `cadence_seconds`. The `build_order.md` must already be **approved**
(②'s own gate) — `autopilot` drives it, it does not plan or approve it.

### 2. Validate before arming
- **`cadence_seconds < per_tick_timeout_seconds`** — refuse to start otherwise (the whole
  hung-vs-slow distinction, the backstop's liveness check, and lock reclaim depend on this ordering).
- `build_order.md` exists and is approved; `runDir` is writable; the scheduling tools are available.
If any check fails, stop and report — do not arm a half-valid run.

### 3. Approve (AskUserQuestion)
Present the full config — which `build_order` it will drive, the six limit values, the cadence, and
the kill-switch path — and get a single human approval. State plainly: this will run **unattended**,
re-invoking ② on a schedule, until the build finishes or a limit halts it; the human can stop it
anytime by creating the kill-switch file or `/autopilot stop`.

### 4. On approval
- Write `autopilot.md` (Config + initial State: `status: running`, `run_started_at`, zeroed counters)
  **atomically**.
- Arm the schedule (Phase: Schedule) — the primary `ScheduleWakeup` and the durable backstop.
- The run is now live. (`/autopilot status` reads `autopilot.md`; `/autopilot stop` halts it.)

---

## Phase: Schedule — arm the pair

On approval (and on every resurrection), arm both:
- **Primary** — `ScheduleWakeup(delay = cadence_seconds, prompt = "/autopilot tick")`: the normal
  in-session heartbeat. Re-armed at the end of each successful tick.
- **Backstop** — `CronCreate(cron = <sparse, on the order of per_tick_timeout>,
  prompt = "/autopilot tick", durable: true)`: created **once** per run, its id recorded in
  `backstop_cron_id`. `durable: true` so it **survives a session death** and can resurrect the run.
  Re-created only if missing.

---

## Phase: Tick — one unit, guarded

Each `/autopilot tick` (fired by the primary OR the backstop) runs exactly this, and **at most one at
a time** (the lock):

1. **Acquire the lock** (atomic `mkdir`/`O_EXCL`). Lost → another tick holds it → **exit**, no work. [R3.1]
2. **Backstop idempotency.** If this fire is the backstop and a primary tick is alive — `lease_renewed_at`
   fresh, or a primary wake is due within `cadence_seconds` — **no-op + exit**; do not double-drive.
   Take over only when the lease is stale past `per_tick_timeout`. [R5.1 / R5.2]
3. **Enter-checks (Phase: Govern).** Re-derive the six limits from the **durable counters** + the
   kill-switch file **before any work**; if any trips → **halt** and exit. Increment and flush
   `tick_count` at entry (so a mid-tick death can't under-count). [R4.2 / R4.3 / R4.4]
4. **Drive one unit.** `Skill(harness-ops:build-order, args="resume mode: unattended")` — ② does the
   next unit and updates `build_order.md` / `progress.md`. Renew `lease_renewed_at` at this governor
   boundary. **No live session is touched** — this is a normal skill call, not a keystroke into a TUI. [R1.1 / R1.4 / R3.3]
5. **Account (Phase: Govern).** Update counters from the outcome — park / crash / escalation. See Phase: Govern.
6. **Complete.** Set `last_tick_completed_at`, **release the lock**, and re-arm the primary
   `ScheduleWakeup` for the next tick. If the build is finished (all features `done` in
   `build_order.md`) → `status: done`, `CronDelete` the backstop, final notify.

A **resurrection** (the backstop firing after a death) runs the same Phase: Tick — step 2 makes it
take over only a genuinely-dead primary, and step 6 re-arms the primary, restoring the cadence.

---

## Phase: Govern — the six limits, halt, and accounting

The governor decides **nothing about the work** — only mechanical threshold checks (counter vs limit).

### Enter-checks (re-derived from the durable counters at EVERY tick entry)
A resurrected tick must halt itself even if a prior `status: halted` write was lost — so the
**authority is the counters**, not the flag (the flag is only a fast-path short-circuit):

| Limit | Trips when | On trip |
|-------|-----------|---------|
| wall-clock | `now − run_started_at > wall_clock_cap_hours` | halt |
| max-tick (= cost cap) | `tick_count > max_ticks` | halt |
| consecutive-park | `consecutive_parks ≥ consecutive_park_cap` | halt + alert |
| crash-loop | `count(recent_crashes within window_minutes) ≥ crash_loop.max` | halt + alert |
| kill-switch | the `killswitch_path` file exists | halt immediately |
| per-tick-timeout | a prior tick's lease is stale past `per_tick_timeout` | → counted a **crash** (below), not a direct halt |

The **kill-switch and these re-derivations run at every tick entry AND when the backstop fires**, so a
human can stop even a hung primary, and a resurrected tick halts from the persisted counters.

### Halt procedure
1. Write `status: halted` + `halt_reason` **first** (smallest window).
2. `PushNotification` the reason (with the done/parked/blocked summary for park/crash/kill).
3. `CronDelete` the backstop (best-effort) — a surviving cron's next fire re-derives halt and self-deletes.
4. Release the lock. **Halt is sticky** — it never auto-resumes; only `/autopilot start` re-invoked by a
   human restarts it (re-arm schedule, reset counters).

### Accounting (after a unit, in Phase: Tick step 5)
`build-order` already records the work outcome in `build_order.md`; `autopilot` only reads it and updates
its meters — it never re-judges:
- **Progress** (a feature went `done` this unit) → reset `consecutive_parks` to 0.
- **Park / escalation** (a feature went `parked`, any reason; an escalation surfaces a parked feature) →
  `consecutive_parks++`, and **relay** the escalation via the existing `PushNotification` /
  `loop-escalation.md` channel — `autopilot` invents no new channel and never overrides loop's fence.
- **Crash** (a tick that started but never recorded completion — `last_tick_started_at` set,
  `last_tick_completed_at` not, lease stale past `per_tick_timeout`) → append `now` to `recent_crashes`.
  This is detected by a *later* tick/backstop, which then **reclaims** the stale lock atomically
  (`rename`, never `rmdir`+`mkdir` — see the lock section). [R3.2]

### Crash is provisional; slow ≠ crashed
A reclaimed "hung" tick's crash is **provisional**: if the *same session's* original tick later records
completion (it was merely slow, under a well-sized `per_tick_timeout`), the crash is **retracted**.
Across a session **death** the original never runs again, so the crash **stands** — which is safe (it
fails toward halting, and a false halt is recoverable by a human re-start).

---

## Resurrection bound (stated, not papered over)

The durable backstop resurrects a hung/dead **tick within a running Claude REPL**. It cannot resurrect
a **total** death — if the REPL / host process is gone, there is nothing for the cron to fire in. That
recovery needs a human to relaunch the REPL (or an OS-level `crontab` outside Claude, which is beyond
`autopilot`'s scope). So "resurrection" means *recover a hung/dead tick in a live REPL*, **not**
*survive the machine being gone*. (Tighter, sub-unit hung detection would need ②/loop to heartbeat the
lease mid-unit — out of scope, since it would touch ①/②.)

---

## Rules

1. **Never drives a live session** — Model A only. No tmux `send-keys`, no `/compact` injection, no
   keystrokes into any live Claude session. The fresh-tick model (read disk → one unit → exit) needs
   none, which is exactly how the "no driving live sessions" rule is honored *by construction*.
2. **Judgment = 0** — `autopilot` only schedules ticks, enforces the six limits, and relays
   escalations. It never decides whether work is correct and never re-plans ②.
3. **Reuse, don't reimplement** — it drives ② via `Skill(harness-ops:build-order)`; it contains no
   gate / maker ≠ checker / lesson / orchestration logic. ① (loop) and ② (build-order) are unchanged.
4. **The durable ledger is the authority** — `autopilot.md` is written atomically (temp + rename); the
   **counters** (re-derived at every tick entry), not the `status` flag, decide a halt; never `TaskCreate`.
5. **A true mutex** — at most one tick at a time: atomic create-or-fail acquire (`mkdir`/`O_EXCL`) AND
   atomic reclaim (`rename`), never `rmdir`+`mkdir`, never read-then-write.
6. **Approve once, up front** — no unattended run starts on an unapproved config, and
   `cadence < per_tick_timeout` is validated before arming.
7. **The fence is hard** — escalations are relayed and the feature parks; `autopilot` continues with
   independents (via ②) but never pushes through loop's autonomy boundary.
8. **Halt is sticky and fails safe** — a tripped limit halts and stays halted until a human re-starts;
   a false halt is preferred to a runaway. Resurrection needs a live REPL (a total death needs a human).
