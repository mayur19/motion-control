# TMB-027 — Implement slow-swing calibration on both controllers

**Status:** Ready — TMB-026 complete

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


