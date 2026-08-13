# Spec: beta

## Meta
- **Status**: approved

## Goal
Fixture spec B — declares a surface that INTERSECTS alpha's and takes an incompatible
decision on the same surface, so both the overlap and contradiction tiers have work.

## Declared Surface
declared-surface:
- src/api/handlers/*.ts
- src/shared/config.ts
depends_on: []

## Decisions
### D1: Use Postgres for session storage
- **Status**: resolved
- **Rationale**: needs concurrent writers; rejected SQLite (single-writer).

## Requirements
### R1: Store sessions
