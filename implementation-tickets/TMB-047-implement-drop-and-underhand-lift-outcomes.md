# TMB-047 — Implement drop and underhand-lift outcomes

**Status:** Blocked — shot-outcome dependency incomplete  
**Labels:** `gameplay`, `detection`  
**Estimate:** 1 day  
**Dependencies:** TMB-046

### Implementation steps

1. Define gameplay-space drop and lift intent boundaries.
2. Map angle, swing plane, timing and game context to distinct trajectories.
3. Tune with representative replays from both phones.
4. Add distinct visual feedback.

### Acceptance criteria

- All four shot outcomes are intentionally reachable.
- Ambiguous low-confidence input resolves predictably rather than randomly.
- Outcome mapping is tunable without altering the early-swing detector.

### Evidence

- Four-shot replay/outcome matrix


