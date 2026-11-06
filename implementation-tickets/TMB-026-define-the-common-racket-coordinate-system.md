# TMB-026 — Define the common racket coordinate system

**Status:** Done

**Labels:** `detection`, `protocol`, `architecture`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-025 (`GO`)

### Implementation steps

1. Define phone grip orientation and common racket X/Y/Z axes.
2. Define left-handed and right-handed transforms.
3. Define neutral orientation and acceptable calibration range.
4. Add diagrams and numeric examples.

### Acceptance criteria

- The same physical motion has the same sign and axis meaning on both phones.
- Handedness does not require separate gameplay logic.
- The definition is precise enough for automated fixture tests.

### Evidence

- `docs/racket-coordinate-system.md`
- `protocol/racket-coordinate-fixtures.json`
- `apps/host-godot/motion/racket_frame.gd`
- `apps/host-godot/tests/racket_frame_test.gd`
- `apps/controller-ios/Sources/Motion/MotionCoordinateAdapter.swift`
- `apps/controller-android/app/src/main/java/com/motionbadminton/controller/android/motion/MotionSampler.kt`

### Implementation log

- 2026-11-06: Defined the shared portrait device axes, neutral-relative
  quaternion convention, right/left proper-rotation transforms, canonical
  quaternion sign, calibration acceptance ranges and numeric examples.
- Added a language-neutral fixture set plus a host reference implementation and
  headless fixture test. Future Swift/Kotlin calibration code must consume the
  same fixtures rather than defining platform-specific signs.
- Normalized native inputs at their source: iOS inverts Core Motion attitude to
  the protocol's device-to-reference convention, and Android now samples
  gravity-free linear acceleration rather than total acceleration.


