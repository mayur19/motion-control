# TMB-028 — Implement host calibration application and verification

**Status:** Review — evidence recorded; live F5 overlay confirmation pending

**Labels:** `detection`, `host`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-027

### Implementation steps

1. Apply calibration bias and orientation transforms before detection.
2. Store calibration only for the active session initially.
3. Plot raw and normalized axes side by side in debug mode.
4. Add fixture tests for both phone coordinate systems and both hands.
5. Detect invalid quaternion/transform results and pause the controller.

### Acceptance criteria

- Fixture motions normalize to equivalent axes within tolerance.
- Raw packet logs remain unchanged; normalized values are recorded separately.
- Invalid calibration never reaches the detector.

### Evidence

- Calibration fixture test output
- Raw versus normalized plots

### Implementation record

- `motion/calibration_normalizer.gd` gates detection input: calibration is
  stored per controller for the host's active session only (dropped on
  session rotation), accepted only from the paired controller's IP, and an
  invalid calibration or transform pauses the controller until a new valid
  `CALIBRATION` arrives.
- `MotionIngest` keeps raw sample axes unchanged, attaches common-frame
  values as `normalized`, and emits `normalized_sample_received` only for
  calibrated samples; that signal is the sole detector input.
- Logging: packet records are unchanged; new `calibration_state` events and
  opt-in `normalized_sample` records (`--log-normalized-motion`) hold raw and
  normalized axes side by side (`docs/log-schema.md`).
- Debug: F5 shows a live raw-vs-normalized gyro plot; `tools/plot-normalization.py`
  renders raw vs normalized PNGs from a session log.
- Tests: `calibration_normalizer_test` (session scoping, pause/resume,
  invalid calibration), `calibration_ingest_test` (raw unchanged, detector
  stream, spoofed/unpaired CALIBRATION ignored, rotation),
  `calibration_normalization_fixture_test` (iOS/Android yaw origins, tilts,
  biases, both hands -> same axes, max error 0.000006; mutation-checked),
  `normalization_plot_test`, and `tools/test_plot_normalization.py`.
- Known limits: the controller is not told when the host pauses it (no
  protocol message); duplicate/reordered sequences still reach the
  normalized stream and are left to the detector (TMB-030+) to de-duplicate.
- Evidence (2026-11-06): `docs/evidence/TMB-028-host-calibration.txt` and the
  physical iPhone plot `docs/evidence/TMB-028-raw-vs-normalized-iphone.png`
  (3192 normalized samples; vector lengths preserved to 4e-7). The first F5
  attempt showed nothing because the plot was laid out below the 720 px
  window; fixed in `a84d785` as a bottom overlay.

