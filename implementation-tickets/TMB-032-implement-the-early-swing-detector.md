# TMB-032 — Implement the early-swing detector

**Status:** Review — iPhone tune defaults selected; cross-device/held-out and backswing handling pending

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

### Implementation record

- Owner decision (2026-11-06): start TMB-032 before TMB-030 data. Thresholds
  are provisional; tuning is TMB-033 on the TMB-030 tune split.
- Finding from the TMB-029 iPhone demo capture (3 smash swings): 5 rotation
  peaks above 4 rad/s, consistent with backswing + forward-swing pairs, and a
  shaft-axis rotation share that varies from 14% to 96% between swings. A
  shaft-twist rejection rule would discard real swings, and the first strong
  rise is often the backswing. Backswing vs forward-swing handling needs
  labeled swings (TMB-030).
- Implemented `detection/early_swing_detector.gd` (`early_rise`, default in
  `DetectorPipeline`; the TMB-029 probe is kept as `angular_speed_probe`):
  rate-aware rise over a 40 ms sensor-time window, onset speed, re-arm
  hysteresis and refractory, an optional shaft gate (off by default), and
  events with source-sample time, detector time and a heuristic confidence.
- Acceptance evidence (synthetic + real development capture): at most one
  trigger per swing; triggers before the peak (220 ms synthetic; 160/260 ms
  on two real swings); about 2 µs per sample; live and replay events identical.
  The real capture also showed one missed slow swing; see
  `docs/swing-detection.md`.
- TMB-033 iPhone tune selection (2026-11-07): change defaults from 3.0 to
  9.5 rad/s onset and from 350 to 700 ms refractory; keep rise 20 rad/s²,
  40 ms window, re-arm 1.5 rad/s, shaft gate off and preprocessing at 25 Hz.
  On S1–S3/N1–N3 this produced count-based 95.6% recall, 96.6% precision and
  0.51 non-swing triggers per 10 minutes. See the versioned TMB-033 report.
- Remaining: Galaxy and left-hand/player tune coverage, one-time held-out
  evaluation, live idle/handling verification, and the backswing question.

