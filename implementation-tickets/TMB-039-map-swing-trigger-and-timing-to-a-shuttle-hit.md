# TMB-039 — Map swing trigger and timing to a shuttle hit

**Status:** Blocked — shot-intent/gameplay dependencies incomplete  
**Labels:** `gameplay`, `detection`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-034, TMB-038

### Implementation steps

1. Define early, perfect, late and miss timing windows relative to intercept.
2. Consume each swing event at most once.
3. Map timing and base shot intent to an initial return trajectory.
4. Add tunable grace windows for first-time players.
5. Log the source swing, timing delta and resolved outcome.

### Acceptance criteria

- A swing outside the active window cannot hit the shuttle.
- The same replayed swing and game state produce the same outcome.
- Timing rather than maximum force dominates successful play.

### Evidence

- Timing-window test matrix
- Replay-to-game deterministic test


