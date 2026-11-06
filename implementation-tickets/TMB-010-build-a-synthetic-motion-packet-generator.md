# TMB-010 — Build a synthetic motion-packet generator

**Status:** Done  
**Labels:** `networking`, `observability`, `quality`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-009

### Implementation steps

1. Create a command-line or Godot-headless tool that emits valid `MOTION` packets at a configurable rate.
2. Add predictable sine-wave motion data and monotonically increasing sequence/timestamps.
3. Add flags for loss, duplicates, reordering, delay, invalid packets and two simulated controllers.
4. Print a run summary on exit.

### Acceptance criteria

- The tool can sustain 200 packets/second per simulated controller for 10 minutes.
- Every impairment mode is deterministic when given a seed.
- Output packets pass the protocol codec.

### Evidence

- Tool usage documentation
- One clean and one impaired run summary

### Implementation log

- 2026-11-06: Added a seeded Ruby CLI generator with sine-wave motion, monotonic
  sequences/timestamps, one or two controllers and all requested impairments.
- 2026-11-06: A paced two-controller run sustained 200.248 packets/s/controller.
- 2026-11-06: A fast logical 10-minute, two-controller run generated and codec-
  validated 240,000 packets with zero internal rejections.
- Clean and deterministic impaired summaries are saved under `docs/evidence`.


