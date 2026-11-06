# TMB-042 — Implement scoring, serve rotation and rematch

**Status:** Blocked — gameplay/AI dependencies incomplete  
**Labels:** `gameplay`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-036, TMB-041

### Implementation steps

1. Implement adjustable rally-point scoring.
2. Define serve ownership and point transitions.
3. Add match-complete and rematch flows.
4. Add automated tests for win threshold, ties/deuce if enabled and rematch reset.

### Acceptance criteria

- A complete one-player match can start, score, end and rematch without debug controls.
- Score and serve state agree after pause/resume.
- Rematch retains controller pairing but resets game state.

### Evidence

- Scoring test output
- Complete match recording


