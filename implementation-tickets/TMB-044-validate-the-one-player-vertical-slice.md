# TMB-044 — Validate the one-player vertical slice

**Status:** Blocked — vertical-slice dependencies incomplete  
**Labels:** `quality`, `gameplay`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-040, TMB-042, TMB-043

### Implementation steps

1. Complete a five-minute practice session on each phone separately.
2. Complete a full scored match against the AI.
3. Verify setup, calibration, pause and rematch without developer intervention.
4. Record detection failures, confusing outcomes and frame-time regressions.

### Acceptance criteria

- Both phones can independently control a complete one-player match.
- No critical defect requires a debug restart.
- Frame timing and controller metrics remain inside the accepted budgets.

### Evidence

- One-player validation report and logs


