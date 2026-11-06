# TMB-034 — Derive normalized shot intent

**Status:** Blocked — detector evaluation dependency incomplete  
**Labels:** `detection`, `gameplay`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-033

### Implementation steps

1. Define a platform-neutral shot-intent structure: trigger time, timing, power, direction, racket angle and confidence.
2. Estimate power and direction from a short, bounded post-trigger window.
3. Clamp and normalize output ranges.
4. Mark low-confidence/insufficient-data outcomes explicitly.
5. Add replay fixtures showing slow, medium and fast representative swings.

### Acceptance criteria

- The gameplay layer receives no device-specific axes or model identifiers.
- Power is monotonic for the representative controlled swing set.
- Waiting for refinement does not delay the initial trigger feedback.

### Evidence

- Shot-intent contract
- Replay output table


