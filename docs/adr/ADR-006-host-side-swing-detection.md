# ADR-006: Detect swings on the host for Release 1

## Context

Both phone platforms need consistent, observable tuning, and early detector
thresholds will change as labeled data is collected.

## Decision

Stream calibrated or raw motion samples to the host and run the Release 1 swing
detector there. Controllers do not classify shots.

## Consequences

One detector implementation can be replayed, tuned and instrumented for both
devices. Detection depends on network delivery, increases host responsibility
and may need reassessment if measured latency cannot meet Gate A.

## Status

Accepted

## Date

2026-11-06
