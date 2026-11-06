# TMB-028 — Implement host calibration application and verification

**Status:** Blocked — calibration dependency chain incomplete  
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


