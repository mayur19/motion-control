# Architecture overview

A concise map of the system as it exists today. The original design and its
rationale are in the
[architecture and delivery plan](../Two-Phone%20Motion%20Badminton%20Architecture%20and%20Delivery%20Plan.md);
accepted decisions are in the [ADRs](adr/README.md).

## System

```text
 Phone (iOS / Android)                         Desktop host (Godot 4.7)
 ─────────────────────                         ───────────────────────────────────────────
 Sensor adapter ──► Motion streamer ──UDP──►   PairingServer / SessionManager
   Core Motion        one MOTION per sample     ConnectionManager (heartbeat, states)
   Android sensors    no batching, no resend    HostClockService ◄─► ClockSynchronizer
 Pairing client ◄──── HELLO / WELCOME ──────►   MotionIngest (validate, age, stale-drop)
   QR or manual code                              │
 Calibration ──────── CALIBRATION ──────────►     ▼
   neutral grip +                               CalibrationNormalizer ─► common racket frame
   slow swing                                     │ normalized_sample_received
 Status / heartbeat ─ STATUS every 500 ms ──►     ▼
                                                DetectorPipeline
                                                  MotionPreprocessor (one-pole low-pass)
                                                  EarlySwingDetector (early_rise)
                                                  │
                                                  ▼
                                                (M3+) fixed-step game simulation
 Cross-cutting on the host: SessionLogger (JSONL), SoakTelemetry, DiagnosticsHud,
 MotionCapture (F6) + CaptureReplayer, RawLatencyStimulus (F4), AwdlDetector
```

## Design rules

| Rule | Why | ADR |
| --- | --- | --- |
| Native Godot desktop host first | Lowest-risk path to measuring latency; one project for Windows, macOS, Linux | [001](adr/ADR-001-native-godot-desktop-host.md) |
| Native Swift and Kotlin controllers | Direct control of sensor rate, timestamps, foreground and Wi-Fi behaviour | [002](adr/ADR-002-native-swift-and-kotlin-controllers.md) |
| Unicast UDP, no retransmission | A late sample has no gameplay value; freshness beats completeness | [003](adr/ADR-003-unicast-udp-motion-transport.md) |
| Fixed, versioned binary protocol | Predictable parsing; shared golden vectors across three languages | [004](adr/ADR-004-versioned-binary-protocol.md) |
| Host-generated QR pairing | Avoids flaky cross-platform discovery during feasibility | [005](adr/ADR-005-host-generated-qr-pairing.md) |
| Swing detection on the host | One observable, replayable detector for both phones | [006](adr/ADR-006-host-side-swing-detection.md) |
| Fixed-timestep simulation | Game outcomes independent of display rate and packet arrival | [007](adr/ADR-007-fixed-timestep-simulation.md) |
| Log raw motion and derived events | Detection errors are reproducible, not anecdotal | [008](adr/ADR-008-raw-motion-and-event-logs.md) |
| Browser/TV only after game feel is proven | Distribution work must not hide interaction risk | [009](adr/ADR-009-platform-expansion-after-game-feel.md) |
| Handedness travels in the calibration packet | Detector code never branches on hand | [010](adr/ADR-010-carry-handedness-in-calibration.md) |
| Core Motion attitude is device-to-reference | Physical evidence; no iOS quaternion inversion | [011](adr/ADR-011-core-motion-attitude-is-device-to-reference.md) |

Further non-negotiables: no Windows-only APIs in core code; every motion packet
carries a monotonic sensor timestamp and sequence number; the host drops stale
motion instead of waiting; safety prompts and pause-on-disconnect are release
requirements.

## Protocol v1 in one table

Big-endian, 28-byte common header (`magic 0x4D42 "MB"`, version, type, flags,
lengths, 64-bit session ID, 32-bit controller ID, 32-bit sequence), maximum
datagram 256 bytes. Full contract: [protocol/spec.md](../protocol/spec.md).

| Type | Message | Direction | Payload | Purpose |
| ---: | --- | --- | ---: | --- |
| 1 | `HELLO` | phone → host | 28–153 B | Pairing secret, platform, capabilities, device/app/OS strings |
| 2 | `WELCOME` | host → phone | 24 B | Player 1/2 or rejection reason, heartbeat/timeout, host clock |
| 3 | `PING` | either | 16 B | Clock-sync request |
| 4 | `PONG` | either | 32 B | Clock-sync reply with receive/send times |
| 5 | `MOTION` | phone → host | 52 B | Sensor time (ns), accel (m/s²), gyro (rad/s), quaternion, flags |
| 6 | `CALIBRATION` | phone → host | 56 B | Neutral quaternion, accel/gyro bias, quality, result, handedness |
| 7 | `STATUS` | either | 20 B | Battery, sensor/app state, pause reason, actual Hz; heartbeat |
| 8 | `GOODBYE` | either | 16 B | Clean disconnect |

Sequence numbers compare with modulo-2³² half-range arithmetic. Reserved fields
and unknown flags are rejected, not ignored. The golden vectors in
`protocol/golden-vectors/` (positive and negative cases) must encode and decode
identically in Swift, Kotlin and GDScript.

## Session lifecycle

```text
 host start ─► QR (session id + 128-bit secret, expires 120 s)
 phone scan ─► HELLO ─► WELCOME (player, controller id)
           ─► PING/PONG × n (offset, RTT) ─► CALIBRATION ─► MOTION stream
 heartbeat: STATUS every 500 ms
   Connected ─(>1 s silent or bad sensor)─► Degraded ─(>2 s)─► Disconnected
   Paused when the app leaves the foreground
 rejoin within the reservation window (default 30 s) ─► same player and id,
   stored calibration resent automatically
 NEW PAIRING CODE ─► new session; every phone must rescan; calibrations dropped
```

See [pairing](pairing.md), [reconnect](reconnect.md) and
[clock synchronization](clock-synchronization.md).

## Motion pipeline

```text
 MOTION datagram
   → codec + header validation
   → session / endpoint / controller gate
   → sequence (loss, duplicate, reorder) and clock-adjusted sample age
   → stale drop (late samples never delay the game)
   → CalibrationNormalizer: bias removal + common racket frame
        (raw axes kept; `normalized` attached; uncalibrated samples never reach detection)
   → MotionPreprocessor: causal low-pass, real Δt, gap reseed, duplicate drop
   → EarlySwingDetector: onset speed + rise rate + refractory + hysteresis
   → swing event (sensor time, arrival time, confidence, speed, rise rate)
   → (M3+) timing window → shuttle response → audiovisual feedback
```

Live play and offline replay run the same `DetectorPipeline`, and a replayed
capture produces identical detector events. Documents:
[racket frame](racket-coordinate-system.md),
[preprocessing](motion-preprocessing.md),
[swing detection](swing-detection.md).

## Host source map (`apps/host-godot/`)

| Folder | Key scripts | Responsibility |
| --- | --- | --- |
| `protocol/` | `protocol_v1.gd` | Encode/decode and validate every message |
| `session/` | `pairing_server.gd`, `session_manager.gd`, `awdl_detector.gd` | QR payload, HELLO handling, player assignment, AWDL warning |
| `network/` | `connection_manager.gd`, `host_heartbeat.gd`, `clock_synchronizer.gd`, `host_clock_service.gd`, `motion_ingest.gd` | Liveness states, clock offset, ingest and sample age |
| `motion/` | `racket_frame.gd`, `calibration_normalizer.gd` | Common racket frame and calibration gate |
| `detection/` | `motion_preprocessor.gd`, `early_swing_detector.gd`, `detector_pipeline.gd` | Filtering and swing triggers |
| `capture/`, `replay/` | `motion_capture.gd`, `capture_replayer.gd`, `replay_capture.gd` | Labeled capture and headless replay |
| `latency/` | `raw_latency_stimulus.gd` | Full-screen flash for camera latency tests |
| `logging/` | `session_logger.gd`, `soak_telemetry.gd` | JSONL session logs and per-second telemetry |
| `ui/` | `diagnostics_hud.gd`, `capture_panel.gd`, `motion_signal_graph.gd`, `normalization_plot.gd` | HUD, F5 plot, F6 panel |
| `addons/greaby_qrcode/` | vendored | MIT QR code generator |
| `tests/` | `*_test.gd` | Headless tests; each prints `TMB-…_OK` |

## Controller source map

| iOS (`apps/controller-ios/Sources/`) | Android (`…/controller/android/`) | Role |
| --- | --- | --- |
| `Motion/MotionSampler.swift` | `motion/MotionSampler.kt` | Read sensors at the highest stable rate |
| `Motion/MotionCoordinateAdapter.swift` | `motion/` | Native boundary to protocol conventions |
| `Motion/MotionStreamer.swift` | `network/` | One UDP datagram per sample |
| `Pairing/` (QR scanner, join payload, client, liveness) | `pairing/` | Join, handshake, heartbeat, rejoin |
| `Protocol/ProtocolV1.swift` | `protocol/` (incl. `ProtocolClock.kt`) | Codec and wire clock |
| `ControllerState.swift`, `ContentView.swift` | `ControllerState.kt`, `MainActivity.kt` | UI state machine, calibration and recalibrate |

## Observability

Every host run writes a JSONL session log (schema in [log-schema.md](log-schema.md)):
a header with versions and settings, packet records, and events for pairing,
clock sync, state changes, calibration, detector triggers, latency stimulus,
AWDL state and per-second soak telemetry. Readers ignore an incomplete final
line, so a crash never invalidates earlier records. Logs never contain audio,
video or personal data, and session IDs are stored as decimal strings because
JSON numbers lose 64-bit precision.

## Tools (`tools/`)

| Tool | Purpose |
| --- | --- |
| `packet-generator/motion_packet_generator.rb` | Synthetic MOTION traffic for ingest tests |
| `soak-report.py` | Rates, loss, lateness, jitter, RTT and frame timing from a log window |
| `check-reconnect-log.py` | Physical reconnect checks |
| `latency-frames.py` | Frame-counting assistant for 240 fps latency videos |
| `plot-clock-sync.rb` | Clock-offset stability plot |
| `plot-normalization.py`, `plot-preprocessing.py` | Raw vs normalized, and before/after filter plots |
| `capture-labels.py` | List, verify and append label corrections for captures |
| `dataset-inventory.py` | Dataset totals against TMB-030 targets |
| `detector-evaluation.py` | Tune/held-out detector reports through the live pipeline |
| `test_no_external_data.py` | Fails if third-party dataset files are tracked |

Every tool has a pytest suite in the same folder: `python3 -m pytest -q tools/`.
