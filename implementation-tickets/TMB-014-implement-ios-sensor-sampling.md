# TMB-014 — Implement iOS sensor sampling

**Status:** Done  
**Labels:** `controller-ios`, `observability`  
**Estimate:** 1 day  
**Dependencies:** TMB-005, TMB-009

### Implementation steps

1. Read device motion using native monotonic sensor timestamps.
2. Request 200 Hz initially and measure the actual callback rate.
3. Normalize values to protocol units without changing coordinate axes yet.
4. Move samples through a bounded queue that never blocks the sensor callback.
5. Show requested rate, actual rate, dropped local samples and sensor status in the debug panel.
6. Stop sampling whenever the application is not in an active foreground session.

### Acceptance criteria

- The physical iPhone records at least 100 stable samples/second for 10 minutes.
- Sample timestamps are strictly monotonic.
- Entering the background stops streaming/sampling and produces a state transition.
- Queue overload has an explicit drop policy and counter.

### Evidence

- Ten-minute on-device sampling summary
- Foreground/background test record

### Implementation log

- 2026-11-06: Added 200 Hz Core Motion sampling, native monotonic timestamps,
  protocol-unit normalization, a bounded drop-oldest queue, rate/drop/status
  diagnostics and foreground-session lifecycle control.
- 2026-11-06: Added passing automated tests for queue overload and strictly
  monotonic admission; simulator build/test evidence and debug-panel screenshot
  are in [TMB-014/015 evidence](../docs/evidence/TMB-014-015-ios-motion.txt).
- 2026-11-06: Completed a 639-second physical iPhone 17e run at median 101 Hz
  with strictly monotonic timestamps and verified immediate background pause.


