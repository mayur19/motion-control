# TMB-015 — Stream iOS motion packets to the host

**Status:** Done  
**Labels:** `controller-ios`, `networking`  
**Estimate:** 1 day  
**Dependencies:** TMB-011, TMB-014

### Implementation steps

1. Add a debug host/port entry before QR pairing exists.
2. Encode and send one `MOTION` datagram per sample.
3. Add sequence, controller and temporary session identifiers.
4. Display sent rate, network errors and most recent successful send time.
5. Run an iPhone-to-host 10-minute stream.

### Acceptance criteria

- Live iPhone motion is visible in the host graphs.
- The host measures at least 100 packets/second for 10 minutes.
- Packet loss is below 1% on the reference LAN.
- No application-level batching or retransmission is present.

### Evidence

- Host log and HUD screenshot
- iOS send summary

### Implementation log

- 2026-11-06: Added temporary host/port controls and a dedicated UDP worker that
  encodes one protocol-v1 `MOTION` datagram per queued sample with temporary
  nonzero session/controller identifiers and monotonic sequence numbers.
- 2026-11-06: Added sent-rate, error and last-success diagnostics. Automated
  tests verify one decodable 80-byte datagram per sample; see
  [TMB-014/015 evidence](../docs/evidence/TMB-014-015-ios-motion.txt).
- 2026-11-06: Completed a 639-second physical iPhone-to-host stream: median
  100.316 accepted packets/s, 0.5274% inferred loss, no duplicate/reordered
  packets and no queue drops. The raw-log checksum is retained in the evidence.


