# TMB-031 — Implement motion preprocessing

**Status:** Blocked — calibration/dataset dependencies incomplete  
**Labels:** `detection`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-028, TMB-030

### Implementation steps

1. Implement bias removal and common-axis transform.
2. Implement the minimum required smoothing/filtering.
3. Measure and document filter group delay or effective trigger delay.
4. Handle irregular sample intervals and small gaps explicitly.
5. Add deterministic fixture and replay tests.

### Acceptance criteria

- Replay produces identical preprocessed output across repeated runs.
- Filter latency is measured and included in the latency budget.
- Gaps do not produce non-finite values or false large spikes.

### Evidence

- Before/after plots
- Filter latency measurement


