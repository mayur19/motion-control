# Motion preprocessing (TMB-031)

Implementation: `apps/host-godot/detection/motion_preprocessor.gd`, run inside
`DetectorPipeline`, so live play and offline replay preprocess identically.

## Pipeline position

```text
MOTION datagram → codec → CalibrationNormalizer (bias removal + common racket
frame, TMB-028) → normalized_sample_received → MotionPreprocessor → detector
```

Raw samples and the session log are unaffected; preprocessing output exists
only inside the detector path and in replay series exports.

## Filter

A causal one-pole low-pass on normalized angular velocity and acceleration
(per axis), with a rate-aware coefficient `α = 1 − exp(−2π·f_c·Δt)` computed
from the real sensor interval `Δt`. Default `f_c = 25 Hz`. Outputs:
`angular_velocity`, `acceleration`, `angular_speed` = |filtered ω|,
`angular_accel` = d(angular_speed)/dt, `dt_ms` and `gap_reset`.

This is deliberately minimal. Detection wants the earliest gyro rise (PRD), so
smoothing is limited to suppressing sample-to-sample jitter.

## Measured delay

From `tests/motion_preprocessor_test.gd` (synthetic swing-shaped rise to
8 rad/s over 300 ms, crossing times interpolated between samples):

| Sample rate | Threshold-crossing delay at 3.5 rad/s | Steady ramp lag |
| --- | --- | --- |
| 100 Hz (iPhone) | 2.6 ms | 2.6 ms |
| 250 Hz (Android) | 4.6 ms | 4.6 ms |

These match the discrete filter's theoretical lag `Δt·(1−α)/α`. Both stay
below the continuous time constant `1/(2π·f_c)` = 6.4 ms, which is the upper
bound as the sample rate rises. The PRD latency budget now includes this
stage.

On the TMB-029 iPhone capture (5220 samples at 10 ms intervals) the filter
changed the angular speed by 0.018 rad/s RMS (0.056 rad/s RMS during the
swings) and the peak from 8.51 to 8.48 rad/s. Quiet-segment noise (0.052 rad/s
s.d.) was essentially unchanged, because Core Motion already smooths the iPhone
gyro. The filter mainly matters for Android's rawer, faster stream. Plots:
`docs/evidence/TMB-031-before-after-swing-iphone.png` and
`docs/evidence/TMB-031-before-after-full-iphone.png`.

## Irregular intervals and gaps

- Every step uses the real `Δt`. Irregular spacing changes `α`, never the
  output scale.
- Duplicate or slightly out-of-order sensor times (`−max_gap_ms ≤ Δt ≤ 0`)
  are dropped (`non_monotonic`).
- A larger backward jump (`Δt < −max_gap_ms`) means a new stream on the same
  controller id (another phone, or a restarted sensor clock). It reseeds like
  a gap, and the detector clears its refractory/arm state for that controller,
  instead of dropping the new stream until its clock catches up.
- Non-finite or missing normalized values are dropped (`non_finite`,
  `not_normalized`), and filter state is kept.
- A gap above `max_gap_ms` (default 50 ms, i.e. 5 missing iPhone samples) reseeds
  the filter from the new sample with `gap_reset = true` and
  `angular_accel = 0`. The filter never bridges or interpolates across a gap,
  so a gap cannot produce a derivative spike.

## Open items

- The TMB-033 iPhone tune selection retained `f_c = 25 Hz`; its 2.6 ms iPhone
  lag remains small relative to the selected detector's 89.9 ms median
  trigger-to-following-peak lead, and the detector met aggregate tune targets
  without changing preprocessing. Re-check the cutoff against Galaxy's rawer,
  250 Hz data before final evaluation.
