# autopilot.md — <run name>

> The durable run-control ledger for an unattended overnight build. Approved by a
> human once (config), then the governor's source of truth across every tick — it
> survives compaction AND session death. Written atomically (temp + rename). The
> single-flight lock is a separate atomic lockfile (`<runDir>/.tick.lock`), NOT a
> field in this file.

## Config   (human-approved before the run starts)
- build_order: <path/to/build_order.md>
- cadence_seconds: 240               # primary ScheduleWakeup delay; MUST be < per_tick_timeout
- per_tick_timeout_seconds: 900      # upper bound on a single ② unit (size to the slowest unit)
- wall_clock_cap_hours: 12
- max_ticks: 200                     # doubles as the cost cap (no token meter exists)
- consecutive_park_cap: 3
- crash_loop: { max: 3, window_minutes: 10 }
- killswitch_path: <runDir>/STOP

## State   (the durable authority for halting — re-derived at every tick entry)
- status: running                    # running | halted | done
- halt_reason: —
- run_started_at: <ts>
- tick_count: 0                      # incremented + flushed at tick ENTRY (before gated work)
- last_tick_started_at: —
- lease_renewed_at: —                # fresh ⇒ in-flight; stale past per_tick_timeout ⇒ hung
- last_tick_completed_at: —
- consecutive_parks: 0
- recent_crashes: []                 # timestamps, for the M-in-N crash-loop window
- backstop_cron_id: —                # CronDelete this on halt

<!--
Invariants:
- cadence_seconds < per_tick_timeout_seconds (validated at start; refuse otherwise).
- A tick acquires <runDir>/.tick.lock via mkdir/O_EXCL (atomic); reclaim a stale lock via rename
  (atomic), never rmdir+mkdir.
- Halt is authoritative via these counters, not the status flag alone; status is a fast-path.
- autopilot never drives a live session: no tmux send-keys, no /compact injection.
-->
