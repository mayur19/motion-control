# Two-Phone Motion Badminton PRD

Nov 4, 2026 · @Mayur

## Summary

Build a two-player badminton game for the HP Victus laptop, played by swinging an iPhone 17e and a Pixel 10 Pro as controllers. The first release should target under 50 ms from swing start to the on-screen reaction, with no custom hardware unless the phones fail that test.

The game reads swing timing, power, type and racket angle, then moves each player automatically into position. It does not attempt 1:1 tracking of the player's hand.

## Goals and success measures

The product succeeds when swings feel immediate and two people choose to play again. The targets below are starting points and should be revised after the first real measurements.

| Measure | Target | How to test |
| --- | --- | --- |
| Swing-to-screen latency, typical (median) | Under 50 ms | 240 fps video of phone and screen |
| Swing-to-screen latency, worst 1% | Under 80 ms | Same video test, plus logged packet timing |
| Dropped or late motion packets | Under 1% | Sequence numbers logged during a 10-minute session |
| Real swings detected | At least 95% | 100 labeled test swings per phone |
| False swings | Under 1 per 10 minutes | Normal play and idle handling |
| Game frame rate | Steady 144 fps | In-game frame-time log |
| Replay intent | Both players want another match | Playtest after five matches |

**Non-goals for the first release:** 1:1 hand or racket tracking, tennis, online multiplayer, custom hardware, console support, and app-store release.

## Users and core experience

The first users are two people playing in the same room on one laptop screen. They should get from opening the game to a live rally in under one minute.

1. Open the game on the laptop and start a match.
2. Open the phone app on each phone and join by scanning a QR code or entering a room code.
3. Secure the phone with the wrist strap and complete a short swing calibration.
4. Play a rally by timing each swing as the shuttle arrives.
5. See the score, then choose a rematch.

## Functional requirements

The requirements below are all in scope for the first release.

| ID | Area | Requirement |
| --- | --- | --- |
| P1 | Phone apps | Provide native Swift and Kotlin apps with the same pairing, calibration and controller flow. |
| P2 | Phone apps | Stream gyroscope, accelerometer and orientation data at the fastest stable rate each phone supports. |
| P3 | Phone apps | Keep the screen awake and the app in the foreground during play. |
| P4 | Phone apps | Show connection status and pause streaming if the app leaves the foreground. |
| L1 | Laptop game | Discover or pair one or two phones on the local network and assign them to Player 1 and Player 2. |
| L2 | Laptop game | Reconnect a dropped phone without ending the match. |
| L3 | Laptop game | Provide a debug view for packet rate, packet loss, jitter and detected swings. |
| G1 | Gameplay | Detect swing start, power, direction and racket angle from the motion data. |
| G2 | Gameplay | Support at least overhead smash, clear, drop and underhand lift shots. |
| G3 | Gameplay | Move each player automatically to the shuttle's predicted landing area. |
| G4 | Gameplay | Score singles matches with a simple, adjustable rally-point format. |
| G5 | Gameplay | Let either phone play a one-player game against at least one computer opponent. |
| G6 | Gameplay | Provide tuning controls for swing thresholds, timing window and shuttle physics. |

## Latency and technical requirements

The laptop should use Ethernet and the phones should use 5 GHz Wi-Fi, so each packet crosses only one wireless hop. This setup is the baseline for all latency testing.

&#91;embedded content: controller data path · two phones to one laptop\]

The budget below is a planning estimate. Real measurements replace it after the first prototype.

| Stage | Budget (ms) |
| --- | --- |
| Sensor sampling | 5–10 |
| Phone processing and network | 5–15 |
| Motion preprocessing filter (measured, TMB-031) | 2.6 (100 Hz) – 4.6 (250 Hz) |
| Game processing at 144 fps | About 7 |
| Display response | 10–15 |
| **Total** | **27–47** |

- **Transport:** Send each sample immediately over UDP, with no batching. Include the player ID, sequence number, timestamp and motion values.
- **Late data:** Discard stale packets rather than delaying the game to wait for them.
- **Android:** Use low-latency Wi-Fi mode and the highest stable sensor rate on the Pixel.
- **iPhone:** Test the fastest stable motion rate on the iPhone 17e and keep the app in the foreground.
- **Laptop:** Target Windows 11 and Godot, plugged in, on the NVIDIA GPU, with V-Sync off.
- **Swing detection:** Trigger from the early gyroscope rise, then use a short prediction window to place the hit.
- **Instrumentation:** Log packet timing, swing detection and frame timing from the first prototype.

## Safety requirements

No one should play at full speed until the phone is physically secured.

- Require a confirmation that a wrist strap or tether is attached before each session.
- Tell players to clear the space around them, including the laptop, people, pets and fragile objects.
- Start each new player with a slow-swing calibration.
- Reward timing over raw force, so hard swings are not necessary to play well.
- Pause the game if a phone disconnects, so a player does not keep swinging blindly.

## Milestones, risks and decisions

Gate 1 comes first because latency decides whether phones can remain the controller. The durations assume part-time work and are rough estimates.

&#91;embedded content: delivery roadmap · 3 phases and 3 gates\]

| Risk | Effect | Response |
| --- | --- | --- |
| Wi-Fi spikes | Occasional missed or late shots | Test on the planned network and tune Android Wi-Fi mode. |
| Phone sensor limits | Slower or weaker detection on one phone | Tune each platform separately and measure both. |
| Swing false positives | Unwanted shots during play | Require a calibrated threshold and log every trigger. |
| Phones are awkward to swing | Players avoid hard swings | Test a strap early and reward timing over force. |
| Game feel misses the mark | Low replay value | Stop at Gate 2 or redesign before building more content. |
