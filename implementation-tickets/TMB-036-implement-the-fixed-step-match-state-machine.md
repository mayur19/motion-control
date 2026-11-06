# TMB-036 — Implement the fixed-step match state machine

**Status:** Blocked — swing laboratory gate has no `GO` decision  
**Labels:** `gameplay`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-035 (`GO`)

### Implementation steps

1. Add Waiting, Serve, Rally, Point, Paused and MatchOver states.
2. Run state updates on a fixed simulation step independent of rendering.
3. Define valid transitions and reject duplicate/out-of-state events.
4. Add deterministic tests for serve, rally end, pause, resume and rematch.

### Acceptance criteria

- Identical scripted inputs produce identical match outcomes at 60, 120 and 144 Hz rendering.
- State transitions are logged.
- Pausing cannot award or lose a point.

### Evidence

- State diagram and automated tests


