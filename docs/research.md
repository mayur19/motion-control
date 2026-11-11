# Research notes

Last updated: 2026-11-11.

This page collects what the project has learned, how each result was
measured, and what is still unknown. It summarizes; the linked reports, ticket
implementation logs and `docs/evidence/` files hold the full data and
checksums.

## How to read the results

Every number here belongs to one category, and the category is always stated:

| Category | Meaning |
| --- | --- |
| **Physical measurement** | Real phones, real network, real host, recorded logs (and video where noted) |
| **Stage-attributed bound** | Measured software stages plus a stated, conservative allowance for stages that could not be measured directly |
| **Owner-accepted exception** | The project owner accepted an alternative to the planned evidence; recorded explicitly, never presented as a measurement |
| **Synthetic / automated** | Deterministic tests on generated data; they prove mechanics, not real-world performance |
| **Tune-split result** | Detector metrics on data used to choose thresholds; optimistic by construction |

Test setup unless stated otherwise: host Mac14,9 (Apple M2 Pro), macOS, Godot
4.7.2, Wi-Fi only on 5 GHz channel 48; iPhone 17e; Samsung Galaxy M14 5G
(Android 15). One operator. The PRD's reference setup (Windows laptop on
Ethernet, Pixel phone) was not available, so results are reported for the
hardware actually used.

## 1. Latency: can phones be controllers?

**Question.** Does a phone swing reach the screen within the PRD targets
(median < 50 ms, p99 < 80 ms)?

**Method.** The host's `--latency-test` mode turns the whole screen from black
to white the first time a sample's raw angular speed crosses 3.5 rad/s. A
240 fps phone camera films the controller and the display together. Each
trigger logs the phone sensor time (clock-adjusted), host arrival, threshold
decision and render-marker time. `tools/latency-frames.py` helps count video
frames. Procedure: [end-to-end latency plan](test-plans/end-to-end-latency.md).

**What went wrong first.** In the first recording the phone rotated toward and
away from the lens. The gyro detected rotation the camera could not see, so the
flash sometimes appeared *before* visible motion. A visible-onset rule then
gives only a lower bound. The second recording rotated the phone in the image
plane. Even then, deliberate gradual acceleration makes "first visible motion"
a poor start boundary, because it mixes the gesture and the detector into a
transport measurement.

**Accepted boundary.** Start = the first logged sample crossing the raw
threshold; end = first visible display change. This isolates
controller + network + host + display latency; detector lead time is studied
separately in M2.

**Result (Galaxy, 41 triggers; stage-attributed bound).**

| Stage | Median | p95 | p99 / max |
| --- | ---: | ---: | ---: |
| Adjusted sensor sample → host render marker (logged) | 30.1 ms | 42.6 ms | 54.1 ms |
| + 17.5 ms display allowance (one 120 Hz refresh, panel response, one camera frame) | **≤ 47.6 ms** | | **≤ 71.6 ms** |

27 display transitions in the 240 fps video were correlated with their render
events (render-to-video phase spread 11.95 ms), which supports the allowance.
An earlier run's stage breakdown (103 triggers) showed where the time goes:
sample → arrival median 10.5 ms (phone send + Wi-Fi), arrival → threshold
0.1 ms, threshold → render marker median 3.7 ms (waiting for the next frame).

**iPhone.** Owner-accepted exception: the owner exercised the iPhone on the
same setup and observed equivalent behaviour. No separate iPhone percentile set
exists.

**Conclusion.** Gate A `GO`. Custom hardware and phone-side early detection are
not needed. Full record: [Gate A decision](test-plans/gate-a-decision.md).

## 2. Network: two phones over Wi-Fi

**Question.** Can both phones stream simultaneously with < 1% loss + late
samples?

**Method.** Both phones in one host session, moved by hand with apps in the
foreground; `tools/soak-report.py` computes rates, loss, lateness (> 50 ms
sample age), jitter, RTT and frame timing from the JSONL log. Owner-shortened
runs (5 minutes instead of 10). [Soak report](test-plans/m1-soak-report.md).

**Result (physical measurement).**

| | iPhone, AWDL on | Galaxy, AWDL on | iPhone, AWDL off | Galaxy, AWDL off |
| --- | ---: | ---: | ---: | ---: |
| Accepted rate, median | 100.0 Hz | 249.1 Hz | 100.0 Hz | 249.2 Hz |
| Loss + late | 24.6% ✗ | 23.2% ✗ | **0.12%** ✓ | **0.17%** ✓ |
| Sample age p95 | 102 ms | 91 ms | **19.6 ms** | **19.5 ms** |
| RTT median | 17.0 ms | 16.8 ms | 17.2 ms | 16.5 ms |
| Duplicates / reordered | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

### Finding: macOS AWDL stalls Wi-Fi input

With default settings, late samples arrived in ~100 ms bursts **every 0.52 s,
on both phones at once**, while host frames did not stall on that rhythm. The
delay was in the Mac's Wi-Fi receive path: Apple Wireless Direct Link (used by
AirDrop, Handoff and other Continuity features) periodically takes the radio to
another channel. Disabling it (`sudo ifconfig awdl0 down`) cut late samples from
about 23% to about 0.15% and sample-age p95 from about 100 ms to about 20 ms.

Product consequences: the host detects an active `awdl0` interface on a Wi-Fi
host, logs `awdl_state` and warns on the pairing panel. An Ethernet host
avoids the issue and also removes one wireless hop. Anyone building a
latency-sensitive LAN game on a Wi-Fi Mac is likely to hit this.

**Still open.** The Ethernet-host run (to quantify the two-wireless-hop
penalty) has not been possible on this machine.

## 3. Clock synchronization

**Problem.** Sample age and latency need the phone's sensor time in host time.
Phones and host have independent monotonic clocks.

**Method.** Standard four-timestamp exchange (`PING`/`PONG`) every 5 s:
RTT = (t4 − t1) − (t3 − t2), offset = ((t2 − t1) + (t3 − t4)) / 2. The estimator
keeps 32 exchanges, takes the median offset of the lowest-RTT quartile, smooths
with α = 0.2, applies steps > 5 ms immediately, and reports drift in ppm.
[Details](clock-synchronization.md).

**Results.**

- *Physical (iPhone, 10.5 min, 128 exchanges):* offset range 3.09 ms, median
  exchange RTT 6.3 ms. Plot: `docs/evidence/TMB-020-iphone-clock-stability.svg`.
- *Synthetic:* asymmetric path bias and five simulated minutes of 100 ppm
  drift are tracked correctly.
- *Estimator artifact found and fixed:* rapid startup exchanges re-ranked by RTT
  produced a spurious −198,804 ppm drift. Drift baselines now advance only when
  the selected sample moves forward by at least one second.

### Finding: Android timestamp time bases

The Android app first mixed `SensorEvent.timestamp` (elapsed-realtime base)
with `System.nanoTime()` for `PONG`. On a phone that had slept ~18 h since boot,
every sample appeared ~66,000 s in the future, and the spec's future-sample rule
would have discarded all of them. Fix: use `elapsedRealtimeNanos` for every wire
timestamp (`ProtocolClock.kt`). Post-fix median sample age: 8.3 ms. Lesson: on
Android, sensor timestamps include deep sleep; `nanoTime` does not.

## 4. Sensors on iOS vs Android

| Aspect | iPhone 17e (Core Motion) | Galaxy M14 (Android sensors) |
| --- | --- | --- |
| Delivered rate | ~100 Hz | ~250 Hz |
| Gyro smoothness | Already smoothed by Core Motion; quiet noise ~0.05 rad/s s.d. | Rawer stream; filtering matters more |
| Attitude | Device-to-reference quaternion (`xArbitraryZVertical`, no magnetometer), sent unchanged | Game rotation vector (falls back to rotation vector), sent unchanged |
| Acceleration | Gravity-free `userAcceleration`, converted to m/s² | Gravity-free `TYPE_LINEAR_ACCELERATION` |

**Finding: Core Motion attitude is device-to-reference.** The original frame
specification inverted the iOS quaternion. The first physical calibration then
rejected every correct grip. An upright portrait iPhone reports pitch +90° with
quaternion (sin 45°, 0, 0, cos 45°), which rotates +Y onto vertical. The
inversion was removed ([ADR-011](adr/ADR-011-core-motion-attitude-is-device-to-reference.md)).

**Finding: iOS magnetometer accuracy.** Neutral capture initially always failed
on iOS because the magnetic-field accuracy reported "uncalibrated" for a frame
that does not use the magnetometer. The non-magnetic frame now reports its own
accuracy value.

**Common racket frame.** Both phones are mapped into one right-handed racket
frame with explicit handedness, so detection never branches on platform or hand
([racket coordinate system](racket-coordinate-system.md),
[ADR-010](adr/ADR-010-carry-handedness-in-calibration.md)). Calibration was
physically verified on both phones with both hands, within the owner's limits
of 0.05 m/s², 0.10 rad/s and 5°.

## 5. Preprocessing: how much smoothing?

The PRD asks for the *earliest* gyro rise, so smoothing must be minimal.

**Design.** Causal one-pole low-pass per axis, coefficient
α = 1 − exp(−2π·f_c·Δt) from the *real* sample interval, f_c = 25 Hz. Gaps over
50 ms reseed the filter instead of interpolating, so a gap cannot create a
derivative spike. Duplicate and slightly out-of-order samples are dropped.
[Details](motion-preprocessing.md).

**Measured delay (synthetic swing-shaped rise).**

| Rate | Threshold-crossing delay |
| --- | ---: |
| 100 Hz | 2.6 ms |
| 250 Hz | 4.6 ms |

Both match the discrete filter's theoretical lag Δt·(1 − α)/α and stay under the
continuous time constant of 6.4 ms.

**Physical effect (iPhone capture).** RMS change in angular speed 0.018 rad/s
(0.056 during swings); peak 8.51 → 8.48 rad/s. On the iPhone the filter barely
matters; on Android's rawer 250 Hz stream it is expected to matter more
(re-check pending).

## 6. Swing detection

### Design

The `early_rise` detector fires when, for a calibrated controller:

1. it is armed and the refractory period (700 ms) has passed;
2. filtered angular speed ≥ 9.5 rad/s;
3. speed rose by ≥ 20 rad/s² over the last 40 ms of *sensor* time (rate
   independent);
4. optional shaft-rotation gate (off by default, because real swings ranged
   from 14% to 96% shaft rotation).

It re-arms only when speed falls below 1.5 rad/s (hysteresis), giving at most
one trigger per swing. Cost is about 2 µs per sample. Live and replay produce
identical events. [Details](swing-detection.md).

### Why rules, not ML

Explainable, calibrated signal processing comes first: it is debuggable,
tunable per device and needs little data. A compact offline-trained classifier
will be evaluated only if rules miss the accuracy gate on a varied dataset
(architecture plan, section 6).

### Tuning result (tune split; iPhone; right hand; one player)

The initial defaults (3.0 rad/s onset, 350 ms refractory) produced 502 triggers
for 90 swings and 19.8 non-swing minutes. Walking alone produced 52–64 triggers
per session. Raising the onset to 9.5 rad/s and the refractory to 700 ms gave:

| TP | FN | FP | Recall | Precision | False triggers / 10 min | Median lead before peak |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 86 | 4 | 3 | 95.6% | 96.6% | 0.51 | 89.9 ms |

By speed: gentle 28/28, fast 27/28 (one extra trigger), normal 31/34 (but the
normal counts were operator estimates). Full report:
[TMB-033 iPhone tune v1](evidence/TMB-033-iphone-tune-v1.md).

**This is not an acceptance result.** It is optimistic by construction (the
same data chose the thresholds), covers one phone, one hand and one player, and
uses count-based matching.

### Evaluation method and its limits

- **Session-level split, decided before recording.** Per phone, sessions S1–S3
  and N1–N3 are `tune`; S4 and N4 are `heldout`. Held-out data is evaluated
  exactly once with a frozen configuration; the tool requires
  `--confirm-heldout` and refuses to overwrite archived reports. A later
  detector change needs a newly designated held-out set.
- **Count-based matching.** Labels give a swing count per take, not a time per
  swing. TP = min(count, triggers), and so on. A miss plus an extra trigger in
  the same take cancel out, which is why per-take tables are always shown.
- **Trigger-to-peak lead** is an event-to-signal estimate. It can pick a
  backswing peak and cannot observe negative lag.
- **Hard negatives matter.** Idle, handling and walking takes are recorded
  deliberately; walking was the largest source of false triggers with the
  initial defaults.

[Detector evaluation guide](detector-evaluation.md) ·
[Dataset capture plan](test-plans/tmb-030-dataset-capture-plan.md) ·
[Capture format](capture-format.md).

## 7. Datasets

### Own dataset (TMB-030)

Captured with the host's F6 panel: immutable `raw.jsonl` (every accepted
datagram, byte-exact) with a SHA-256 file, plus append-only `labels.jsonl`
(shot, speed, hand, player, swing count; corrections append revisions). Sessions
are capped at 6 minutes for the operator's comfort.

| Phone | Tune swings | Tune non-swing min | Held-out | Status |
| --- | ---: | ---: | --- | --- |
| iPhone 17e | 90 | 19.8 | S4/N4 pending | Tune complete |
| Galaxy M14 | 0 | 0 | pending | Not started |

Captures contain sensor data from the owner's own movements and stay in the
host's user-data folder, not in Git.

### Public datasets

[External dataset evaluation](external-dataset-evaluation.md) assessed public
badminton sensor data as an off-domain check. Main conclusions:

- **BadminSense (`BADS_CLL`)** records a smartwatch on the forearm during real
  strokes with shuttle impact. Our phone *is* the racket, and it is swung in the
  air with no impact. Forearm angular speed is a different quantity from racket
  angular speed, so **detector thresholds cannot transfer**.
- It publishes only valid, pre-segmented strokes, so it has **no non-swing
  time**. It cannot measure false triggers per 10 minutes, and recall on
  pre-segmented windows flatters any detector.
- At most it can answer narrow, placement-robust morphology questions (for
  example, does a backswing rise precede the forward swing?).
- Its license is CC BY-NC-ND. It was used locally, for internal non-commercial
  research only. **No data or derived values are in this repository**, and a
  test enforces that.
- Other datasets (MultiSenseBadminton, ShuttleSet, BFMD, video datasets) may
  inform shot taxonomy, rally structure, shuttle trajectories and the AI
  opponent later. None can validate trigger thresholds.

## 8. Open research questions

1. **Backswing vs forward swing.** The first strong rise can be the backswing.
   Should the detector require the forward-swing direction, perhaps learned from
   the calibration practice swing? Needs per-swing timing labels or annotated
   video.
2. **Cross-device transfer.** Do iPhone-tuned thresholds hold on Android's
   250 Hz, less-smoothed stream, or does each platform need its own calibration
   profile?
3. **Generalization.** Left hand, second player, different heights and swing
   styles.
4. **Shot intent (TMB-034).** Can timing, power, direction, racket angle and a
   confidence value separate smash, clear, drop and lift reliably from an air
   swing? What gameplay context is needed?
5. **Prediction horizon.** The detector leads the peak by about 90 ms (median).
   How much of that lead can gameplay use to place the hit, and does it feel
   fair?
6. **Two-hop penalty.** How much does a Wi-Fi host cost compared with Ethernet,
   with AWDL off?
7. **Game feel.** Do players accept automatic movement and timing-based hits?
   Answered only by the Gate B playtest.

## 9. Lessons learned

- Measure transport and gesture separately. Folding gesture acceleration into
  a latency measurement makes both numbers meaningless.
- Check the camera can actually see what the sensor sees before trusting
  frame counts.
- On a Wi-Fi Mac, turn off AWDL before measuring anything.
- Treat every timestamp's time base explicitly, especially on Android.
- Physical tests catch convention errors that unit tests encode faithfully
  (the iOS quaternion inversion passed its own fixtures).
- Decide data splits before recording, and keep held-out data truly unseen.
- Record hard negatives (walking, handling); they dominate false triggers.
- Keep human-in-the-loop sessions short; long sessions produce labeling errors.

## References

- [Product requirements](../Two-Phone%20Motion%20Badminton%20PRD.md)
- [Architecture and delivery plan](../Two-Phone%20Motion%20Badminton%20Architecture%20and%20Delivery%20Plan.md)
- [Architecture decision records](adr/README.md)
- [External dataset sources (machine-readable)](external-dataset-sources.json)
- Ticket implementation logs: [`implementation-tickets/`](../implementation-tickets/README.md)
