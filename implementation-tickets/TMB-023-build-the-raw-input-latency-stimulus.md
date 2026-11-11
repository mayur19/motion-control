# TMB-023 — Build the raw-input latency stimulus

**Status:** Done  
**Labels:** `observability`, `host`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-020, TMB-022

### Implementation steps

1. Add a deliberately simple gyro threshold independent of the final swing detector.
2. On crossing, change a large screen region to a high-contrast color on the next available frame.
3. Emit a synchronized log event containing sample, arrival, threshold and simulation/render marker times.
4. Add a cooldown so one physical swing creates one visual stimulus.
5. Allow threshold adjustment without rebuilding.

### Acceptance criteria

- A controlled swing produces one unambiguous visual response.
- The threshold path contains no batching, animation delay or gameplay logic.
- The log identifies every processing stage available in software.

### Evidence

- [Automated stimulus and logging evidence](../docs/evidence/TMB-023-raw-latency.txt)
- [240 FPS test procedure and stimulus operation](../docs/test-plans/end-to-end-latency.md)
- Physical test-mode video and matching event log

### Implementation log

- 2026-11-06: Added an isolated angular-speed threshold path, full-screen
  high-contrast response, per-controller cooldown and runtime threshold controls.
- 2026-11-06: Added stage timestamps for sample, arrival, threshold, simulation
  marker and next-frame render marker plus a deterministic burst/cooldown/
  threshold test. The path has no animation, batching or gameplay dependency.
- The required physical swing video is deferred until a phone and high-speed
  camera are available; the implementation and log contract are complete.
- 2026-11-11: `--latency-test` no longer arms at startup, where the full-screen
  overlay hid the pairing QR (the workaround was pressing F4 twice). It now
  stays hidden and arms on the first motion sample, which the host only
  delivers after a phone has paired; that arming sample never triggers a flash.
  Any manual F4 toggle cancels auto-arm. Covered by
  `tests/raw_latency_auto_arm_test.gd` (`TMB-023_LATENCY_AUTO_ARM_OK`).
  Automated only; not yet checked on a physical phone.
- 2026-11-11 physical check (iPhone 17e, owner-observed): with
  `--latency-test`, the pairing QR was visible at launch and the phone paired
  without pressing F4. The overlay then appeared on its own with no flash on
  arming, each swing gave about one flash, and F4 returned to the QR and
  re-armed. The session log agrees: pairing, then Connected, with no stimulus
  before pairing and 16 `raw_latency_stimulus` events afterwards at the default
  3.5 rad/s threshold. This was a functional check only: AWDL was active and no
  camera was used, so it is not a latency measurement.


