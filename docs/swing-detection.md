# Early-swing detection (TMB-032)

Implementation: `apps/host-godot/detection/early_swing_detector.gd`
(`early_rise`, the default in `DetectorPipeline`). It runs after
`MotionPreprocessor` (docs/motion-preprocessing.md) on calibrated samples only,
in both live play and offline replay.

## Rule

For each controller, a trigger fires on a sample when all of these hold:

1. The detector is **armed**, and at least `refractory_ms` (700) of sensor time
   has passed since the last trigger.
2. Preprocessed angular speed ≥ `onset_speed_rad_s` (9.5).
3. Speed has risen at ≥ `min_rise_rad_s2` (20) over the last `rise_window_ms`
   (40) of **sensor time**. The rise is measured against real timestamps, so
   the test is independent of the 100 Hz vs 250 Hz sample rate. At least half a
   window of history is required, and history is cleared on every gap reset,
   so a jump across a gap never counts as a rise.
4. Optional directional gate: the share of rotation about the shaft axis
   (`+Y_R`) must be ≤ `max_shaft_fraction`. The default is 1.0 (off): on the
   TMB-029 iPhone capture real swings ranged from 14% to 96% shaft rotation,
   so this gate would have rejected real swings.

After a trigger the controller is **disarmed** until speed falls below
`rearm_speed_rad_s` (1.5, hysteresis). Combined with the refractory period,
this gives at most one trigger per swing, even when speed dips during the
swing.

## Event

| Field | Meaning |
| --- | --- |
| `detector`, `version` | `early_rise`, 1 |
| `controller_id`, `sequence` | Source sample identity |
| `sensor_monotonic_ns` | Controller sensor time of the triggering sample (source-sample time) |
| `detector_time_ns` / `arrival_monotonic_ns` | Host arrival time of that sample: the earliest host time the decision can exist. Deterministic, so live and replay events are identical. |
| `confidence` | Heuristic margin above the speed and rise thresholds, in (0, 1]. Not a calibrated probability. |
| `angular_speed_rad_s`, `rise_rate_rad_s2`, `shaft_fraction` | Values at the trigger |

## Evidence so far

- Synthetic (`tests/early_swing_detector_test.gd`): one trigger per swing at
  100 and 250 Hz, 220 ms before the peak of a 300 ms rise to 8 rad/s. These
  mechanics tests pin an explicit 3.0 rad/s onset and 350 ms refractory so
  their profiles remain independent of data-tuned defaults. They also cover
  slow handling, jitter, a dipped swing, two separated swings, the optional
  shaft gate, gaps, deterministic output and bounded processing cost (about
  2 µs per sample). `detector_pipeline_test.gd` separately locks the tuned
  default configuration.
- Live vs replay (`tests/capture_replay_test.gd`): identical `early_rise`
  events for the same datagrams, including a capture started after calibration
  and a session rotation.
- TMB-029 iPhone demonstration capture (3 smash swings and 10 s idle; a
  development check, not a tuning or evaluation set): 2 triggers in the smash
  take, at 160 ms and 260 ms before their peaks, and 0 in the idle take. The
  first, slowest swing was missed, and no swing triggered twice. The slow
  backswing before the 13.6 s forward swing did not trigger, but that is
  anecdotal.
- TMB-030 iPhone tune split (`S1–S3`, `N1–N3`): the original 3.0 rad/s,
  350 ms defaults produced 502 triggers for 90 count-labeled swings and 19.78
  non-swing minutes. The selected 9.5 rad/s onset and 700 ms refractory, with
  the other defaults unchanged, produced count-based TP 86 / FN 4 / FP 3,
  recall 95.6%, precision 96.6%, and 0.51 non-swing triggers per 10 minutes.
  Median estimated trigger lead to the following peak was 89.9 ms. Exact
  gentle takes were 28/28; exact fast takes were 27/28 with one over-trigger.
  The normal-speed counts in S1 were operator estimates, so their apparent
  31/34 result is not precise ground truth. Full report:
  `docs/evidence/TMB-033-iphone-tune-v1.md`.

## Open questions for TMB-030/033

- Backswing vs forward swing: the first strong rise can be the backswing.
  Whether to require the dominant-axis direction of the forward swing (it
  could be learned from the calibration practice swing) needs labeled data.
- The selected defaults are iPhone-only and right-hand/player-1-only. Galaxy,
  left-hand/player coverage, S4/N4 held-out evaluation and the live
  idle/handling acceptance check are still required. Do not tune on S4/N4.
