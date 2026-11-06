# TMB-021 — Implement heartbeat, disconnect and reconnect

**Status:** Done  
**Labels:** `networking`, `host`, `controller-ios`, `controller-android`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-019, TMB-020

### Implementation steps

1. Add periodic status/heartbeat messages.
2. Define Connected, Degraded, Disconnected and Reconnecting thresholds.
3. Pause sample acceptance immediately when a controller backgrounds or reports invalid sensor state.
4. Retain player assignment for a bounded reconnect window.
5. Re-run clock synchronization after reconnect before accepting motion.
6. Make the host session continue while one controller reconnects.

### Acceptance criteria

- Turning Wi-Fi off produces a visible disconnect within the documented threshold.
- Restoring Wi-Fi reconnects to the same player without restarting the host session.
- Backgrounding either controller pauses its input and shows a host warning.
- Motion is not accepted until post-reconnect synchronization completes.

### Evidence

- [Automated reconnect integration and controller build evidence](../docs/evidence/TMB-021-reconnect.txt)
- [Thresholds, identity and reconnect behavior](../docs/reconnect.md)
- Physical reconnect test matrix for both phones and corresponding host logs

### Implementation log

- 2026-11-06: Added 500 ms STATUS heartbeats on iOS and Android, host
  Connected/Degraded/Paused/Disconnected/Reconnecting state tracking, a 1 s
  degraded threshold, 2 s disconnect threshold and a 15 s identity reservation.
- 2026-11-06: Persisted a non-personal per-install controller identity, retained
  player assignment across endpoint changes and rejected stale-endpoint packets.
- 2026-11-06: Motion now pauses immediately on background/invalid sensor state,
  and reconnect replaces the prior clock estimator so motion cannot resume until
  a fresh PING/PONG completes. The other player and host session remain live.
- 2026-11-06: Physical iPhone Wi-Fi loss produced Paused then Disconnected and
  exposed that the high-rate motion socket could recover while the retained
  Network.framework control path did not. The host correctly rejected that
  unsynchronized motion. iOS now recreates the control socket, re-HELLOs when the
  path is ready and retries for 12 seconds; the host also permits a known
  installation to reclaim its active reservation after QR expiry.
- 2026-11-06: The fixed build passed 12 physical XCTest cases, camera-paired at
  99.6 packets/s and reproduced physical disconnect. After the 15-second
  reservation had already expired, foregrounding automatically re-HELLOed,
  re-synchronized and resumed motion at 81.1 packets/s under a new controller
  ID. A timely same-reservation restore cycle and the Android/Galaxy matrix
  remain pending.


- 2026-11-06: Host session logs now record an allow-listed `pairing` event per
  HELLO outcome (controller ID, player, state, reason, endpoint, platform; no
  secrets, installation IDs or device models), and
  `tools/check-reconnect-log.py` checks a log against these acceptance criteria.
- 2026-11-06: **Timely same-reservation physical restore on iPhone 17e: PASS.**
  Wi-Fi off/on with immediate return to the app re-HELLOed on a new control
  endpoint 9.4 s after Disconnected and received the same controller ID and P1.
  A fresh PING/PONG (RTT 5.2 ms) preceded Connected (171 ms after re-HELLO); the
  25 motion packets that arrived before then were gated, and motion resumed at a
  median 99.9 packets/s. The host session ran throughout.
- 2026-11-06: That run exposed a host telemetry defect: the reconnected iOS
  motion socket legitimately restarts its sender-local sequence at 0, but the
  host kept one sequence window per controller ID, so ~1,624 packets were counted
  as reordered and the old stream's real losses could be erased. The ingest now
  starts a new sequence window when the admitted motion endpoint changes and
  carries prior loss forward (`tests/motion_stream_restart_test.gd`).
- 2026-11-06: Physical iPhone re-run on the fixed host: PASS. The phone rejoined
  with the same ID and P1, 8.0 s after Disconnected. The new socket restarted at
  sequence 0 again, and loss, duplicate, reorder and queue-drop counts stayed at
  0 for 27 s at 92-104 packets/s. All 25 pre-sync motion packets were gated.
  iPhone reconnect acceptance criteria are met physically; the Android/Galaxy
  matrix remains pending.
- 2026-11-06: **Open defect (found physically):** after the host window was
  closed, the iPhone kept showing Connected. Neither controller watches whether
  the host is still alive. iOS/Android `Connected` changes only on
  pairing/foreground events, the host sends no GOODBYE on close, and its only
  regular host→controller traffic is the 5 s clock PING. Host-side disconnect
  detection is unaffected. Proposed fix: host STATUS every 500 ms plus GOODBYE on
  clean close; controllers leave Connected when no host packet arrives within
  WELCOME `disconnect_timeout_ms`, then run the existing re-HELLO loop.
- 2026-11-06: Implemented controller-side host-loss detection. The host sends
  STATUS every 500 ms to live controllers and GOODBYE (host shutdown) on close
  (`tests/host_heartbeat_test.gd`). iOS and Android leave Connected after the
  WELCOME 2 s timeout without host packets, then retry HELLO for 12 s; GOODBYE
  ends the pairing (`HostLivenessTests`, `HostLivenessTest`). Android previously
  had no rejoin path and now reuses the same bounded HELLO exchange. Automated:
  host tests and smoke PASS, 17 iOS simulator tests PASS, 17 Android unit tests
  PASS plus debug APK. Physical verification on the iPhone is pending.
- 2026-11-06: Physical iPhone host-loss checks PASS. Closing the host window
  ended the phone session immediately (GOODBYE). SIGKILLing the host made the
  phone leave Connected and return to pairing/rejoin mode (timeout). The
  stale-Connected defect is fixed on iOS. Detection latency was not timed;
  Android host-loss behavior is unit-tested only.
- 2026-11-06: Physical Galaxy M14 5G (SM-M146B, Android 15) background and Wi-Fi
  reconnect PASS after fixes: Android resume state, a Wi-Fi-bound rejoin with a
  15 s window, and host HUD cards mapped by player. Both reconnects kept the
  same controller ID and P1, with fresh clock sync before any motion was
  accepted. The Wi-Fi recovery used 13.7 s of the 15 s reservation. Background
  longer than about 17 s on Android needs a foreground-service decision.
  Android host-loss (GOODBYE/timeout) is not yet run physically.
- 2026-11-06: Android host-loss checks PASS on the Galaxy. Closing the window
  moved the phone to Not Paired; after a SIGKILL, adb screenshots show PAIRING
  (rejoining) at about 10 s and Not Paired with "host is unreachable" at about
  22 s.
- 2026-11-06: Per owner direction (recovery of 30 s to 1 min, game-dependent),
  the disconnect reservation is configurable: default 30 s, clamped to 5-60 s,
  set with `--reconnect-window-s=N` or `network/reconnect/window_seconds`, and
  logged in `host_started`. iOS and Android retry rejoin for 60 s; the host
  reservation decides player restoration
  (`tests/reconnect_window_test.gd`, `RejoinScheduleTests`, `RejoinPolicyTest`).
  Automated: host tests and smoke PASS, iOS simulator 19/19, Android 23/23.
  Not yet physically re-run with the longer windows.
- 2026-11-06: **Fixed host pairing defect (found physically after the soak):**
  the iPhone was backgrounded for 1.75 s, more than 120 s after the QR was
  issued. It re-HELLOed from a new socket and was rejected as `expired`,
  because it still held its slot (no reservation yet) and the expired-code
  exception only covered reclaiming a disconnect reservation. A known
  controller that still holds its assignment may now move endpoints after
  expiry; the secret and identity are still required, and unknown controllers
  stay barred (`pairing_server_test`: `active_resume=P2`). The Galaxy's
  `wrong_session` HELLOs from a new IP at the same time are not yet explained.
- 2026-11-06: Fixed the remaining session findings:
  - Host: a clock-sync update only completes a reconnect already in progress
    (Reconnecting -> Connected). A late PONG can no longer revive a
    Disconnected or Degraded controller without the STATUS resync that resets
    the clock estimate and motion pin (`tests/connection_state_test.gd`).
  - iOS: retry HELLOs are sent only on a `.ready` path, so no queued burst
    when Wi-Fi returns. STATUS is sent immediately only when foreground or
    sensor validity changes, otherwise every 500 ms (was about 6/s)
    (`ControlTrafficTests`). Simulator and physical iPhone: 21/21 PASS;
    installed.
  - Android: debug-panel values get a weighted, wrapping width instead of
    clipping. 23/23 unit tests PASS; not yet installed or checked on the
    Galaxy (not connected).
