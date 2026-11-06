# TMB-017 — Stream Android motion packets to the host

**Status:** Done  
**Labels:** `controller-android`, `networking`  
**Estimate:** 1 day  
**Dependencies:** TMB-011, TMB-016

### Implementation steps

1. Add temporary debug host/port entry.
2. Encode and send one `MOTION` datagram per sample.
3. Add sequence, controller and temporary session identifiers.
4. Request Android low-latency Wi-Fi behavior only while actively streaming and release it afterward.
5. Run a Pixel-to-host 10-minute stream.

### Acceptance criteria

- Live Pixel motion is visible in the host graphs.
- The host measures at least 100 packets/second for 10 minutes.
- Packet loss is below 1% on the reference LAN.
- Network resources and Wi-Fi mode are released after the session.

### Evidence

- Host log and HUD screenshot
- Android send summary

### Implementation log

- 2026-11-06: Added debug destination controls, one protocol-v1 `MOTION` UDP
  datagram per sample, temporary identifiers/sequences, send diagnostics and an
  active-stream-only Android low-latency Wi-Fi lock.
- 2026-11-06: Streamed Android-emulator motion to the real host at 103–111 Hz
  with zero measured loss/duplicate/reorder; backgrounding stopped networking and
  released the Wi-Fi lock. See [TMB-016/017 evidence](../docs/evidence/TMB-016-017-android-motion.txt).
- The ten-minute physical-Pixel LAN run and <1% loss evidence are deferred by
  explicit project-owner direction until hardware is available.


