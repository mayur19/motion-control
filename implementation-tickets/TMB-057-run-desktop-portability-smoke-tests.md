# TMB-057 — Run desktop portability smoke tests

**Status:** Blocked — release export dependency incomplete  
**Labels:** `release`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-055

### Implementation steps

1. On each OS, start a host session, display the QR and join both phones.
2. Complete calibration, one rally, pause/reconnect and rematch.
3. Record firewall/network permission behavior and frame rate.
4. File platform-specific defects without adding platform logic to gameplay.

### Acceptance criteria

- The smoke sequence passes on Windows, macOS and Linux.
- Both phone platforms work with every host platform tested.
- Known limitations are documented with severity.

### Evidence

- Three-platform smoke-test matrix


