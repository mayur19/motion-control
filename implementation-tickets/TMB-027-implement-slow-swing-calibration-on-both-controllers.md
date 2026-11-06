# TMB-027 — Implement slow-swing calibration on both controllers

**Status:** Review — iPhone physically verified; Galaxy run pending

**Labels:** `detection`, `controller-ios`, `controller-android`, `safety`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-026

### Implementation steps

1. Add neutral-pose capture and handedness selection.
2. Add a guided, controlled slow swing.
3. Validate sensor availability, bias, orientation and minimum motion range.
4. Send versioned calibration data to the host.
5. Reject invalid/unstable calibration with a specific corrective message.

### Acceptance criteria

- Both phones produce data in the common coordinate frame.
- Repeating calibration gives values inside a documented tolerance.
- A phone held in an invalid orientation cannot complete calibration.
- The flow instructs users not to perform full-force swings.

### Evidence

- Calibration test results for both hands and phones

### Implementation record

- iOS and Android use mirrored deterministic neutral and slow-swing validators.
- Pairing now enters Calibration; streaming begins only after a successful
  `CALIBRATION` datagram is sent.
- Both flows require explicit handedness and screen-facing confirmation, show a
  no-full-force warning, and display corrective failure messages.
- Protocol v1 byte 53 now carries handedness; see ADR-010 and regenerated
  cross-language golden fixtures.
- Host ingest retains successful calibration for the active process and applies
  it to subsequent raw motion before publishing common-frame samples. Full
  host visualization and invalid-controller pause behavior remain TMB-028.
- Automated results and commands are recorded in
  `docs/evidence/TMB-027-calibration.txt`.
- Physical iPhone run (2026-11-06) found and fixed three defects: iOS
  accuracy always 0, inverted Core Motion quaternion (TMB-026 adapter), and a
  rejoin dead-end on calibrated phones. Rejoin now resends calibration; both
  controllers have Recalibrate; the host logs a `calibration` event.
- iPhone: invalid orientation rejected; right and left hand each calibrated
  twice; neutral tilt repeats within 2.3°. Accel-bias repeat reached
  0.040 m/s² (right) and 0.027 m/s² (left), above the documented synthetic
  0.02 m/s² tolerance; a physical tolerance needs an owner decision.
- Owner decision (2026-11-06): physical repeatability limits per axis are
  0.05 m/s² accel bias, 0.10 rad/s gyro bias and 5° neutral tilt
  (`docs/racket-coordinate-system.md` §6). iPhone passes them.
- Remaining gap before Done: Galaxy physical run (both hands), checked
  against the same limits. Details in `docs/evidence/TMB-027-calibration.txt`.
