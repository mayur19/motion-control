# ADR-007: Run game simulation on a fixed timestep

## Context

The game must behave consistently at 60, 120 and 144 Hz while motion packets
arrive independently of rendered frames.

## Decision

Run gameplay simulation at a fixed rate of at least 120 Hz and keep input ingest
and rendering decoupled from simulation advancement.

## Consequences

Outcomes become reproducible across refresh rates and suitable for deterministic
tests. The host must manage interpolation, overload and timing queues, and the
higher tick rate consumes more CPU than a 60 Hz simulation.

## Status

Accepted

## Date

2026-11-06
