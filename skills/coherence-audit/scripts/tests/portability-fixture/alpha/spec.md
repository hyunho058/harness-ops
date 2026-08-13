# Spec: alpha

## Meta
- **Status**: approved

## Goal
Fixture spec A — exists to give coherence-audit two declared surfaces that overlap,
so the pinned `capability:run-glob-overlap` procedure is actually exercised under agy.

## Declared Surface
declared-surface:
- src/api/**/*.ts
- src/shared/config.ts
depends_on: []

## Decisions
### D1: Use SQLite for session storage
- **Status**: resolved
- **Rationale**: single-file, no server to run.

## Requirements
### R1: Store sessions
