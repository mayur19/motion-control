# TMB-016 — Implement Android sensor sampling

**Status:** Done  
**Labels:** `controller-android`, `observability`  
**Estimate:** 1 day  
**Dependencies:** TMB-006, TMB-009

### Implementation steps

1. Read accelerometer, uncalibrated/appropriate gyroscope and rotation-vector data with native monotonic timestamps.
2. Request the fastest safe rate required to achieve a stable 200 Hz target, subject to device support.
3. Normalize values to protocol units without changing coordinate axes yet.
4. Use a bounded queue and explicit overload-drop counter.
5. Show requested/actual rate, sensor accuracy and dropped local samples.
6. Stop sampling when the application is not in an active foreground session.

### Acceptance criteria

- The Pixel records at least 100 stable samples/second for 10 minutes.
- Sample timestamps are strictly monotonic.
- Foreground/background behavior matches iOS.
- Sensor callbacks never perform blocking networking work.

### Evidence

- Ten-minute on-device sampling summary
- Foreground/background test record

### Implementation log

- 2026-11-06: Added 200 Hz accelerometer, uncalibrated/fallback gyroscope and
  game/fallback rotation-vector sampling using native `SensorEvent.timestamp`,
  protocol units, a bounded drop-oldest queue and sensor/rate/accuracy counters.
- 2026-11-06: Verified automated queue/timestamp tests, a 101 Hz Android-emulator
  sample rate, zero local drops and the foreground-to-Paused background transition;
  see [TMB-016/017 evidence](../docs/evidence/TMB-016-017-android-motion.txt).
- The ten-minute physical-Pixel record is deferred by explicit project-owner
  direction until hardware is available.


