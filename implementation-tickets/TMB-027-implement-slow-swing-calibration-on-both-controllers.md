# TMB-027 — Implement slow-swing calibration on both controllers

**Status:** Review — implementation and automated evidence complete

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


