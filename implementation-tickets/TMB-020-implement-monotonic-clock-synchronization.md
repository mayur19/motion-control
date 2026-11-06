# TMB-020 — Implement monotonic clock synchronization

**Status:** Done  
**Labels:** `networking`, `observability`, `quality`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-019

### Implementation steps

1. Implement repeated `PING`/`PONG` exchanges with all four timestamps.
2. Estimate RTT and controller-to-host monotonic-clock offset.
3. Prefer low-RTT samples and smooth offset updates without hiding large changes.
4. Repeat synchronization periodically and immediately after reconnect.
5. Convert sensor timestamps into host time for sample-age measurement.
6. Add automated tests for known offset, delay, jitter, asymmetric delay and drift.

### Acceptance criteria

- Synthetic clock tests pass within the documented tolerance.
- Host logs show RTT, offset, drift and clock-adjusted sample age.
- Clock adjustment never causes accepted sample time to move backward silently.

### Evidence

- [Automated estimator and real-UDP integration output](../docs/evidence/TMB-020-clock-sync.txt)
- [Algorithm and tolerance specification](../docs/clock-synchronization.md)
- Five-minute clock stability plot for each phone

### Implementation log

- 2026-11-06: Added immediate and five-second periodic four-timestamp PING/PONG,
  low-RTT sample preference, offset smoothing with visible large steps, drift
  reporting, controller-to-host timestamp conversion and backward-time counters.
- 2026-11-06: Verified synthetic offset/delay/jitter/asymmetry/five-minute-drift
  cases and the complete HELLO → PING/PONG → adjusted MOTION path over UDP.
- 2026-11-06: Physical iPhone logging exposed a transient startup drift spike
  when the low-RTT selector revisited rapid samples. Drift baselines now advance
  only across at least one second of forward host time, with a regression test.
- 2026-11-06: Added a reproducible 10.5-minute physical iPhone clock plot with
  128 observations, 3.093 ms offset range and 6.314 ms median RTT. The eight
  retained pre-fix startup-artifact points are explicitly clipped and annotated.
- The Android oscillator plot remains pending until the available Galaxy
  reference device is connected; the originally planned Pixel is unavailable.


