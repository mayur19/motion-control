# Common racket coordinate system

**Status:** Normative for Release 1

**Ticket:** TMB-026

**Fixture:** `protocol/racket-coordinate-fixtures.json`

This document defines the coordinate contract between native phone sensors,
calibration and host-side swing processing. All detector and shot-intent code
uses the common racket frame defined here; it must not branch on platform or
handedness.

## 1. Native device frame

iOS Core Motion and Android sensors use the same portrait-oriented,
right-handed body axes:

```text
Front of phone, portrait orientation

                  +Y_D
             top / racket head
                     ^
                     |
                     |
        left edge    +--------> +X_D  right edge
                    /
                   / +Z_D  out of the screen
```

- `+X_D`: toward the physical right edge while looking at the screen.
- `+Y_D`: toward the physical top edge.
- `+Z_D`: perpendicular to and out of the screen.
- Positive rotation follows the right-hand rule.
- Vectors use SI units: acceleration in m/s² and angular velocity in rad/s.
- Protocol quaternions are ordered `(x, y, z, w)` and represent active
  device-to-reference rotations.

The app must lock its controller UI to portrait orientation while sampling.
Display rotation must never silently remap sensor axes.

Core Motion's `userAcceleration` is already gravity-removed. Android must
provide gravity-free linear acceleration, either from
`TYPE_LINEAR_ACCELERATION` or by subtracting a synchronized gravity estimate
from `TYPE_ACCELEROMETER`. Total acceleration including gravity must not enter
the common racket transform. Platform filtering differences remain calibration
and preprocessing concerns; they do not change axis signs.

Android's rotation-vector quaternion and Core Motion's attitude quaternion
both already map device coordinates into their reference frame, so both
controllers transmit them unchanged. Physical check: an upright portrait
iPhone reports Core Motion pitch +90°, quaternion `(sin 45°, 0, 0, cos 45°)`,
which rotates `+Y_D` onto vertical `+Z`. (TMB-026 originally inverted the iOS
quaternion; TMB-027's first physical calibration showed this rejected every
correct grip, and the inversion was removed; see ADR-011.) The iOS adapter at the native
sensor boundary is therefore a pass-through; all protocol consumers use the
device-to-reference convention below.

## 2. Required neutral grip

The player holds the phone as the racket handle:

1. portrait orientation, with the top edge pointing toward the virtual racket
   head and away from the wrist;
2. screen facing the player;
3. wrist straight and phone centred in front of the body;
4. selected hand recorded explicitly as `right` or `left`;
5. phone stationary for the complete neutral capture.

The neutral attitude is `q_0`, the normalized device-to-reference quaternion at
capture time. The live attitude is `q_t`. Both platforms must use a
gravity-vertical reference frame; absolute yaw is irrelevant because it is
removed by `q_0`.

For quaternion multiplication `⊗`, define the neutral-relative attitude:

```text
q_rel = inverse(q_0) ⊗ q_t
```

At neutral, `q_rel` is identity `(0, 0, 0, 1)` regardless of the phone's
absolute heading or the platform's arbitrary yaw origin.

## 3. Common racket frame and handedness

The common racket frame `R` is right-handed:

- `+Y_R` is the shaft axis toward the phone top / virtual racket head.
- `+X_R` is the normalized lateral axis.
- `+Z_R = +X_R × +Y_R` is the normalized racket-face axis.

Right-handed grip uses the neutral device basis unchanged. Left-handed grip is
normalized with a 180° proper rotation about `+Y`, not a reflection:

```text
H_right = |  1  0  0 |       h_right = (0, 0, 0, 1)
          |  0  1  0 |
          |  0  0  1 |

H_left  = | -1  0  0 |       h_left  = (0, 1, 0, 0)
          |  0  1  0 |
          |  0  0 -1 |
```

Both matrices have determinant `+1`. Consequently the same transform is valid
for polar vectors (linear acceleration), axial vectors (angular velocity) and
orientation quaternions. A mirrored left-hand sample `(-x, y, -z)` becomes the
same common sample `(x, y, z)` as its right-hand counterpart.

## 4. Transform equations

Bias vectors are stored in native device coordinates and subtracted before
rotation. Let `a_D` and `ω_D` be one live device sample, and let `b_a` and `b_ω`
be the captured biases:

```text
a_R = H_hand · rotate(q_rel, a_D - b_a)
ω_R = H_hand · rotate(q_rel, ω_D - b_ω)

q_R = h_hand ⊗ q_rel ⊗ inverse(h_hand)
```

`q_R` is normalized after multiplication. Because `q` and `-q` encode the same
rotation, implementations canonicalize the result to a non-negative `w`. When
`w` is effectively zero, the first non-zero component in `x, y, z` is made
positive. This removes sign jumps from logs and fixtures.

The host applies these equations to raw `MOTION` samples after protocol,
session and age validation (TMB-028, `motion/calibration_normalizer.gd`):

- `CALIBRATION` is accepted only from a paired controller's paired IP while it
  is Reconnecting, Connected or Degraded, and only for the host's active
  pairing session. Rotating the session (NEW PAIRING CODE) drops all stored
  calibrations.
- Raw sample axes are never overwritten; common-frame values are attached as
  `normalized`, and only those samples are emitted on
  `MotionIngest.normalized_sample_received`, the sole detector input.
- Samples without a calibration for the current session stay raw and never
  reach detection.
- A calibration or sample that yields an invalid transform pauses the
  controller for detection (`calibration_state` event with the reason) until
  a new valid `CALIBRATION` arrives.

Release 1 uses this host path so detector behavior stays replayable. Sensor
flag bit 4 (`calibration applied`) is reserved for a future controller-side
transform; the Release 1 host pauses a controller that sets it.

## 5. Neutral-capture acceptance range

TMB-027 must reject calibration unless all of these conditions hold:

| Check | Required range |
| --- | --- |
| Capture duration | At least 500 ms |
| Accepted samples | At least 50 and at least 100 Hz effective rate |
| Quaternion magnitude | Every sample in `[0.98, 1.02]` |
| Quaternion spread | Maximum angular distance from the mean at most 3° |
| Shaft direction | `+Y_D` within 35° of reference-frame vertical |
| Screen plane | `+Z_D` within 25° of horizontal |
| Gyroscope stillness | Per-axis RMS at most 0.15 rad/s; peak norm at most 0.35 rad/s |
| Linear-acceleration stillness | Per-axis standard deviation at most 0.35 m/s² |
| Gyroscope bias | Per-axis absolute mean at most 0.20 rad/s |
| Handedness | Exactly `right` or `left`; never inferred |

The screen-facing-player instruction cannot be inferred reliably from inertial
sensors, so the calibration UI must show it and ask for confirmation. Failed
captures retain no active transform and must return a specific corrective
reason.

## 6. Controlled slow-swing acceptance range

After neutral capture succeeds, the player performs exactly one controlled
practice swing. Both native controllers apply the same checks:

| Check | Required range |
| --- | --- |
| Capture duration | 600 ms to 3 s |
| Accepted samples | At least 50 and at least 100 Hz effective rate |
| Orientation excursion | 20° to 140° from the first swing sample |
| Peak angular speed | 0.6 to 5.0 rad/s |
| Sensor availability | Acceleration, gyroscope and orientation valid on every sample |

The UI must say “slow, controlled practice swing” and must explicitly prohibit
a full-force swing. Excursion or angular speed below the minimum asks for a
wider controlled arc. Either maximum being exceeded asks the player to slow
down. A successful record includes protocol version 1, the selected hand,
neutral quaternion, acceleration bias, gyroscope bias and quality.

Repeatability is tested with two captures whose acceleration bias differs by
0.01 m/s² on one axis; the accepted records must remain within 0.02 m/s².
That limit applies to the synthetic unit-test fixtures only.

Physical repeatability (owner decision, 2026-11-06): two accepted
calibrations by the same player, hand and phone must agree within

| Quantity | Per-axis limit |
| --- | --- |
| Acceleration bias | 0.05 m/s² |
| Gyroscope bias | 0.10 rad/s |
| Neutral shaft and screen tilt | 5° |

Neutral yaw is not compared, because the reference yaw origin is arbitrary
and the host uses orientation relative to neutral. These limits are about
two orders of magnitude below swing-detection signal levels. The product
does not integrate acceleration into position (no 1:1 tracking; see the PRD).

## 7. Numeric examples

### Handedness

With neutral and live orientation both identity and zero biases:

```text
right raw:  ( 2, 3,  4) -> common (2, 3, 4)
left raw:   (-2, 3, -4) -> common (2, 3, 4)
```

The same mapping applies to acceleration and angular velocity.

### Neutral cancellation

If `q_0 = q_t = (0, 0, 0.70710678, 0.70710678)`, then `q_rel` and `q_R` are
identity. Absolute yaw therefore cannot change detector inputs.

### Live rotation

For a right-handed player with identity neutral and a live +90° rotation about
`+Y`, `q_t = (0, 0.70710678, 0, 0.70710678)`. A device vector `(1, 0, 0)` maps
to approximately `(0, 0, -1)` in the common frame.

## 8. Executable fixture contract

`protocol/racket-coordinate-fixtures.json` is the language-neutral executable
contract. Every future Swift, Kotlin or GDScript implementation must consume
the same cases and match each expected vector and quaternion within the file's
tolerance. `apps/host-godot/tests/racket_frame_test.gd` validates the initial
host implementation.

Platform references:

- [Apple Core Motion processed device motion](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data)
- [Apple `CMMotionManager` device axes](https://developer.apple.com/documentation/coremotion/cmmotionmanager)
- [Apple relative-attitude multiplication](https://developer.apple.com/documentation/coremotion/cmattitude/multiply(byinverseof:))
- [Android sensor coordinate system and rotation vector](https://developer.android.com/reference/android/hardware/SensorEvent)
- [Android quaternion conversion](https://developer.android.com/reference/android/hardware/SensorManager#getQuaternionFromVector(float%5B%5D,float%5B%5D))

