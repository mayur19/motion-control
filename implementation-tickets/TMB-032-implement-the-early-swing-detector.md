# TMB-032 — Implement the early-swing detector

**Status:** Blocked — preprocessing dependency incomplete  
**Labels:** `detection`, `quality`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-031

### Implementation steps

1. Detect the early angular-velocity rise using calibrated axes and rate-aware thresholds.
2. Add directional plausibility constraints.
3. Add a configurable refractory period.
4. Emit detector time, source-sample time and confidence.
5. Ensure live and replay modes emit identical events for identical input.

### Acceptance criteria

- One physical swing produces no more than one trigger.
- The detector operates before the peak of representative swings.
- Detector processing does not block the simulation or render loop.

### Evidence

- Annotated replay plots
- Processing-time profile


