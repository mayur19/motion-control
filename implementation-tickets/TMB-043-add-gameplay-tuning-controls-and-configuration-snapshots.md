# TMB-043 — Add gameplay tuning controls and configuration snapshots

**Status:** Blocked — gameplay dependencies incomplete  
**Labels:** `gameplay`, `observability`  
**Estimate:** 1 day  
**Dependencies:** TMB-039, TMB-041, TMB-042

### Implementation steps

1. Add debug controls for timing windows, shuttle parameters, positioning and AI difficulty.
2. Save/load named tuning snapshots.
3. Store the active snapshot identifier in every playtest log.
4. Prevent debug tuning controls from appearing in normal player mode.

### Acceptance criteria

- A playtest result can be traced to exact gameplay values.
- Invalid configuration values are rejected or clamped.
- Loading the same snapshot reproduces the same scripted test outcomes.

### Evidence

- Example tuning snapshot
- Configuration validation tests


