# TMB-041 — Implement the computer opponent

**Status:** Blocked — gameplay dependencies incomplete  
**Labels:** `gameplay`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-037, TMB-039

### Implementation steps

1. Implement an opponent that selects reachable intercepts and legal returns.
2. Add configurable reaction delay, accuracy and shot selection.
3. Ensure the opponent can intentionally make mistakes.
4. Add a deterministic seeded mode for tests.

### Acceptance criteria

- The opponent can complete rallies and concede points.
- Difficulty can be adjusted without changing player detector thresholds.
- Seeded matches are reproducible.

### Evidence

- AI behavior test cases
- Five-minute practice match capture


