# ADR-008: Store raw motion and derived events in test logs

## Context

Latency and detection defects cannot be diagnosed reliably from player memory
or screenshots alone.

## Decision

Engineering sessions record raw motion, network timing, calibration, detector
events, simulation application and visible frame markers under a unique session
identifier.

## Consequences

Failures can be replayed and measured without reproducing the exact swing. Logs
can be large and may reveal physical motion patterns, so raw capture is opt-in
outside engineering builds and retention must exclude personal account, audio
and video data.

## Status

Accepted

## Date

2026-11-06
