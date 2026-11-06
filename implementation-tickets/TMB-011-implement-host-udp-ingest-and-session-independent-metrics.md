# TMB-011 — Implement host UDP ingest and session-independent metrics

**Status:** Done  
**Labels:** `networking`, `host`, `observability`  
**Estimate:** 1 day  
**Dependencies:** TMB-010

### Implementation steps

1. Bind the host to a configurable UDP port.
2. Parse and validate packets without blocking the render or simulation loop.
3. Track sender endpoint, packet rate, sequence gaps, duplicates, reorder and arrival jitter.
4. Drop malformed packets safely and count rejection reasons.
5. Expose a thread-safe/main-loop-safe sample queue to the future detector.

### Acceptance criteria

- Two synthetic 200 Hz senders run simultaneously without frame stalls.
- Loss, duplicate and reorder counters match configured synthetic impairments.
- Invalid traffic cannot crash or grow memory without bound.

### Evidence

- Automated impairment test output
- Host profiler/frame-time capture

### Implementation log

- 2026-11-06: Added configurable nonblocking UDP ingest, strict codec
  validation, bounded per-frame polling and a bounded detector sample queue.
- 2026-11-06: Added endpoint, one-second rate, gap/loss, duplicate, reorder,
  jitter, age, queue-drop and rejection metrics for two independent senders.
- 2026-11-06: Clean 2×200 Hz input received all 800 datagrams; seeded impaired
  counters matched the generator's receiver-observable counters exactly.
- 2026-11-06: A 500-sample queue stayed bounded under 766 accepted packets and
  reported 266 explicit oldest-sample drops.


