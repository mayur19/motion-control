# TMB-031 — Implement motion preprocessing

**Status:** Review — iPhone cutoff retained; Galaxy re-check pending

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

### Implementation record

- Owner decision (2026-11-06): start TMB-031 before TMB-030's dataset exists.
  Implementation and deterministic tests use synthetic fixtures and the
  TMB-029 demonstration capture; any data-dependent choice (filter cutoff)
  must be re-checked against the TMB-030 tune split before TMB-033.
- Implemented `detection/motion_preprocessor.gd` inside `DetectorPipeline`:
  rate-aware one-pole low-pass (25 Hz), drops duplicate/out-of-order and
  non-finite samples, and reseeds after gaps > 50 ms. Step 1 (bias removal and
  common axes) is TMB-028's normalizer.
- Measured delay: 2.6 ms (100 Hz) and 4.6 ms (250 Hz) threshold-crossing and
  ramp lag; added to the PRD latency budget; documented in
  `docs/motion-preprocessing.md`.
- Evidence: replaying the TMB-029 iPhone capture twice gave identical
  preprocessed series (5220 samples), all finite; before/after plots in
  `docs/evidence/TMB-031-before-after-*-iphone.png`; `tests/motion_preprocessor_test.gd`
  covers gaps, duplicates, non-finite input and irregular intervals.
- TMB-033 retained the 25 Hz cutoff on the iPhone tune split: measured filter
  lag is 2.6 ms at 100 Hz and aggregate detector targets were met without a
  preprocessing change. Remaining before Done: re-check the cutoff on Galaxy
  tune data, where the 250 Hz sensor stream is rawer.

