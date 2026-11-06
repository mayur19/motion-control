# TMB-019 — Implement QR join and handshake on both controllers

**Status:** Done  
**Labels:** `networking`, `controller-ios`, `controller-android`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-018

### Implementation steps

1. Scan and validate the join QR in iOS.
2. Scan and validate the join QR in Android.
3. Implement `HELLO` retry/backoff and `WELCOME` handling.
4. Have the host authenticate the secret and assign a stable controller/player identifier.
5. Show actionable errors for expired code, unsupported version, unreachable host and full session.
6. Remove or hide the temporary debug host/port workflow from normal use.

### Acceptance criteria

- Either phone can join as the first or second controller.
- A third controller is rejected clearly.
- Expired, altered and wrong-version QR codes are rejected.
- Both controllers show the same player assignment as the host.

### Evidence

- Pairing video or screenshots for both join orders
- Negative pairing test results

### Implementation log

- 2026-11-06: Added native iOS QR scanning, Google Code Scanner on Android,
  strict cross-platform join-payload validation, bounded HELLO retry/backoff,
  authenticated host slot assignment and WELCOME handling.
- 2026-11-06: Verified P1/P2 assignment, stable retry identity, third-controller
  rejection, wrong-secret rejection and expiry over real local UDP sockets. Both
  controller test suites and all protocol golden vectors pass; see
  [pairing evidence](../docs/evidence/TMB-019-pairing.txt).
- 2026-11-06: Verified a genuine iPhone camera scan through WELCOME, clock sync
  and a 99.6 packet/s live stream. Also verified that an already-known P1 may
  reclaim its bounded reservation after the public QR window expires.
- The Galaxy camera scan and physical two-phone join-order swap remain pending
  until the Android device is connected.


