# Two-Phone Motion Badminton Architecture and Delivery Plan

Nov 6, 2026 · Derived from the Two-Phone Motion Badminton PRD

## 1. Executive decision

Build a **platform-neutral display host**, not a Windows-only game.

The first production-shaped implementation will be a native Godot desktop application with Windows, macOS and Linux export targets. Windows on the HP Victus remains the reference test environment because it provides the known 144 Hz display and GPU, but no gameplay or networking code may depend on Windows APIs.

The iPhone and Pixel remain native controller applications. They send timestamped motion samples over local-network UDP to the display host. QR pairing is the primary discovery mechanism. Browser and TV hosts are later delivery targets and must not delay validation of latency, swing detection or game feel.

### Why this sequence

1. Native desktop plus UDP provides the cleanest measurement of whether phones are viable controllers.
2. One Godot project can serve the three desktop operating systems without introducing browser networking constraints.
3. Native Swift and Kotlin retain control over sensor sampling, timestamps, foreground behavior and Wi-Fi behavior.
4. Browser and TV builds become rational investments only after the core interaction is proven fun.

## 2. Scope and constraints

### Release 1 scope

- Two native phone controllers: iOS and Android.
- One native Godot display host: Windows first, portable to macOS and Linux.
- One-player practice and two-player local matches.
- QR pairing, calibration, reconnect and pause-on-disconnect.
- Four intended shot outcomes: smash, clear, drop and lift.
- Automatic player positioning.
- Live engineering telemetry and session logs.
- A repeatable end-to-end latency test.

### Explicitly deferred

- Browser host, Android TV, Apple TV and smart-TV packaging.
- App-store distribution and public account systems.
- Internet multiplayer, matchmaking and cloud persistence.
- Machine-learning classification in the runtime.
- 1:1 racket or hand position tracking.
- Custom controller hardware.
- Production art, large content sets and monetization.

### Non-negotiable engineering constraints

- Core game and protocol code cannot call Windows-only APIs.
- Gameplay must continue to behave correctly at 60, 120 and 144 Hz.
- Simulation and rendering must not depend on packet arrival rate.
- Every motion packet uses a monotonic sensor timestamp and sequence number.
- The host discards stale motion rather than delaying the simulation.
- Safety prompts and disconnect pausing are release requirements, not polish.

## 3. Target architecture

```text
┌───────────────────────────┐              ┌───────────────────────────┐
│ iOS controller            │              │ Android controller        │
│ Core Motion               │              │ Android sensor framework  │
│ Calibration + session UI  │              │ Calibration + session UI  │
│ UDP sender                │              │ UDP sender                │
└─────────────┬─────────────┘              └─────────────┬─────────────┘
              │  timestamped binary motion packets       │
              └──────────────────┬────────────────────────┘
                                 │ local 5/6 GHz LAN
                    ┌────────────▼────────────┐
                    │ Native Godot host       │
                    │ Pairing/session manager │
                    │ Clock synchronizer      │
                    │ Motion ingest + logs    │
                    │ Swing detector          │
                    │ Game simulation         │
                    │ Renderer + debug HUD    │
                    └─────────────────────────┘
```

### Component boundaries

| Component | Responsibility | Must not own |
| --- | --- | --- |
| Controller sensor adapter | Read platform sensors and retain native timestamps | Shot classification or game rules |
| Controller session client | Pair, calibrate, transmit, report connection health | Player assignment policy |
| Protocol library | Encode/decode versioned messages and validate fields | Network discovery UI |
| Host session manager | Pair devices, assign players, reconnect and expire sessions | Swing thresholds |
| Clock synchronizer | Estimate device-to-host clock offset and network RTT | Gameplay timing windows |
| Motion ingest | Order, validate, measure and expose recent samples | Rendering |
| Swing detector | Convert recent samples into normalized shot intent | Scoring or shuttle physics |
| Game simulation | Resolve timing, player movement, shuttle and scoring | Platform networking |
| Telemetry/logging | Record raw inputs, events, packet health and frame timings | Runtime decisions |

This separation allows UDP to be replaced with WebRTC for a future browser host without rewriting swing detection or gameplay.

## 4. Architecture decisions

The following decisions are accepted for the first implementation. A change requires a short architecture decision record describing the evidence and impact.

| ID | Decision | Rationale |
| --- | --- | --- |
| ADR-001 | Native Godot desktop is the first display host | Lowest-risk route to latency measurement and cross-platform desktop delivery |
| ADR-002 | Swift and Kotlin controllers remain native | Best access to stable high-rate sensors and foreground/network controls |
| ADR-003 | Use unicast UDP for motion samples | Freshness matters more than retransmission; old samples have no gameplay value |
| ADR-004 | Use a fixed, versioned binary packet format | Predictable parsing and cross-language golden-vector tests |
| ADR-005 | Pair with a host-generated QR code | Avoids unreliable cross-platform discovery work in the feasibility phase |
| ADR-006 | Detect swings on the host for Release 1 | Centralizes tuning and lets both phones use the same observable detector |
| ADR-007 | Run game simulation on a fixed timestep | Decouples game behavior from render refresh and packet timing |
| ADR-008 | Store raw motion and derived events in test logs | Makes detection errors reproducible instead of anecdotal |
| ADR-009 | Keep browser/TV delivery behind the game-feel gate | Prevents distribution work from masking core interaction risk |

## 5. Controller-to-host protocol

### Pairing flow

1. Host starts a local session and displays a QR code.
2. The QR payload contains protocol version, host IP, UDP port, session ID and a short-lived pairing secret.
3. Phone sends `HELLO` with its platform, device model, app version and supported sensor capabilities.
4. Host authenticates the pairing secret, assigns Player 1 or Player 2 and replies with `WELCOME`.
5. Phone and host perform several `PING`/`PONG` exchanges to estimate RTT and monotonic-clock offset.
6. Phone enters calibration, then starts the motion stream.
7. Host accepts motion only from the paired endpoint and session.

The pairing secret prevents another device on the LAN from injecting controller events accidentally. It is session-scoped and is never reused.

### Message set

| Message | Direction | Purpose |
| --- | --- | --- |
| `HELLO` | Phone → host | Pair and declare capabilities |
| `WELCOME` | Host → phone | Confirm session and player assignment |
| `PING` / `PONG` | Both | Estimate RTT, clock offset and connection health |
| `MOTION` | Phone → host | Send one sensor sample immediately |
| `CALIBRATION` | Phone → host | Send neutral pose and calibration result |
| `STATUS` | Both | Battery, sensor state, pause and foreground state |
| `GOODBYE` | Both | End a controller session cleanly |

### Minimum `MOTION` fields

- Protocol version and message type.
- Session identifier and controller identifier.
- Monotonic sequence number.
- Monotonic sensor timestamp in nanoseconds.
- Accelerometer X/Y/Z in m/s².
- Gyroscope X/Y/Z in rad/s.
- Orientation quaternion X/Y/Z/W.
- Sensor accuracy/status flags.

Define the exact byte layout in `protocol/spec.md`. Maintain one set of golden encoded packets that Swift, Kotlin and GDScript must encode and decode identically.

### Runtime rules

- Desired stable sampling rate: 200 Hz; acceptable feasibility floor: 100 Hz.
- Send each sample without application-level batching.
- Do not retransmit motion packets.
- Drop duplicates and packets that arrive outside the reorder allowance.
- Mark a sample stale using its clock-adjusted sensor time, not arrival time alone.
- Re-estimate clock offset periodically and after a reconnect.
- Use reliable messages only for pairing/configuration; they may initially use repeated UDP request/acknowledgement with bounded retries.

## 6. Runtime and gameplay model

### Processing pipeline

```text
Sensor sample
  → validate/session check
  → sequence, loss and age calculation
  → device calibration transform
  → short rolling motion window
  → early-swing trigger
  → shot intent: timing, power, direction, angle, confidence
  → gameplay timing window
  → shuttle response and audiovisual feedback
```

### Timing model

- Run gameplay on a fixed simulation step of at least 120 Hz on the reference host.
- Render at the active display rate; support 60, 120 and 144 Hz without changing game outcomes.
- Process all newly available controller samples before each simulation step.
- Trigger visible/audio feedback on the earliest confident swing rise; refine power and angle over a short bounded follow-up window.
- Record sensor time, host receive time, detector trigger time, simulation application time and rendered-frame marker for every detected swing.

### Detection strategy

Start with explainable, device-calibrated signal processing rather than machine learning:

1. Remove neutral bias and transform axes to a common racket coordinate frame.
2. Smooth only enough to suppress sensor noise; measure the latency introduced by the filter.
3. Detect early angular-velocity rise plus directional constraints.
4. Apply a refractory period to prevent one swing becoming multiple shots.
5. Derive timing and power continuously.
6. Classify the four shot outcomes using swing plane, angle, timing and gameplay context.

If threshold/rule-based classification cannot meet the accuracy gate on a sufficiently varied labeled dataset, evaluate an offline-trained compact classifier. Do not introduce ML before that evidence exists.

## 7. Repository and build structure

Create the following structure when implementation begins:

```text
apps/
  host-godot/
  controller-ios/
  controller-android/
protocol/
  spec.md
  golden-vectors/
tools/
  packet-generator/
  log-analyzer/
  latency-test/
docs/
  adr/
  test-plans/
  playtests/
```

### Continuous integration minimum

- Validate formatting and run unit tests for all three codebases.
- Run protocol golden-vector tests on Swift, Kotlin and GDScript implementations.
- Export a Windows debug build on every main-branch change.
- Add macOS and Linux exports before the portability milestone closes.
- Retain test logs as artifacts for failed latency or detector test runs.

## 8. Delivery plan and quality gates

Effort is expressed in focused developer-days. For one developer, expect approximately 7–9 full-time weeks or 12–16 part-time calendar weeks. Device-specific defects can extend the plan.

| Milestone | Estimate | Deliverable | Exit criteria |
| --- | ---: | --- | --- |
| M0. Foundation | 2–3 days | Repository skeleton, ADRs, protocol v0, build conventions | All three applications build to an empty/runnable shell; protocol fields agreed |
| M1. Instrumented vertical slice | 6–8 days | Both phones stream motion to a host debug view | Each phone sustains ≥100 Hz for 10 minutes; loss <1%; reconnect works; timing log is complete |
| Gate A. Phone feasibility | 1–2 days | 240 fps latency report on both phones | Median swing-to-screen <50 ms and p99 <80 ms, or a documented stage-level cause and approved remediation |
| M2. Swing laboratory | 6–8 days | Calibration, labeled capture tool and real-time detector | ≥95% real-swing detection and <1 false swing per 10 minutes on both phones |
| M3. Playable one-player rally | 8–10 days | Auto movement, shuttle physics, hit timing, scoring and one AI opponent | Five-minute practice match completes without debug intervention; stable reference frame rate |
| M4. Two-player match | 6–8 days | Two controllers, four shot outcomes, reconnect/pause and rematch | Ten consecutive matches without session failure; shot outcomes are distinguishable in blind playtest |
| Gate B. Game feel | 1–2 days | Structured playtest report | Both players request a rematch after five matches; no critical safety or control issue |
| M5. Desktop release candidate | 5–7 days | Windows, macOS and Linux builds; setup guide; telemetry toggle | Protocol compatibility passes; smoke test passes on all targets; release checklist complete |
| Gate C. Platform expansion | 1 day | Browser versus Android TV decision | Expansion target chosen from measured user environment and performance needs |

### Gate policy

- Do not begin M2 until Gate A proves the controller path or identifies a feasible fix.
- Do not build extensive art/content before Gate B.
- Do not begin browser or TV packaging before Gate C.
- A missed gate results in measurement and a design decision, not automatic continuation.

## 9. Executable backlog

### Epic A — Foundation and protocol

| ID | Task | Output / definition of done | Depends on |
| --- | --- | --- | --- |
| A-01 | Pin Godot, Xcode, Android Studio/JDK and language versions | Versions recorded in `docs/development.md`; clean-machine setup verified | — |
| A-02 | Create repository structure and application shells | Host, iOS and Android apps launch and show build version | A-01 |
| A-03 | Write protocol v0 byte layout | `protocol/spec.md` includes sizes, units, byte order and compatibility rules | — |
| A-04 | Create protocol golden vectors | At least one valid packet of every type plus invalid/truncated cases | A-03 |
| A-05 | Implement protocol codecs | Swift, Kotlin and GDScript pass the same vectors | A-04 |
| A-06 | Create ADRs 001–009 | Decisions are committed and linked from the root README | — |

### Epic B — Pairing and transport

| ID | Task | Output / definition of done | Depends on |
| --- | --- | --- | --- |
| B-01 | Start host session and generate QR payload | QR encodes reachable address, port, version, session and expiring secret | A-05 |
| B-02 | Add QR scanning and manual fallback on both phones | Both devices can join; malformed/expired QR is rejected visibly | B-01 |
| B-03 | Implement `HELLO`/`WELCOME` and player assignment | Two phones receive stable, unique assignments | B-02 |
| B-04 | Implement clock synchronization | Logs contain offset and RTT; synthetic offset tests pass | B-03 |
| B-05 | Implement motion streaming and host ingest | Live host graphs update from both devices with sequence/loss/age | B-04 |
| B-06 | Implement heartbeat, foreground pause and reconnect | Host pauses on loss and restores the same player within the reconnect window | B-05 |

### Epic C — Instrumentation and feasibility

| ID | Task | Output / definition of done | Depends on |
| --- | --- | --- | --- |
| C-01 | Define structured session log | Schema covers device, samples, network timing, detector events and frame markers | A-03 |
| C-02 | Build host debug HUD | Per-player Hz, loss, jitter, sample age, RTT and connection state visible | B-05 |
| C-03 | Build visual latency stimulus | A deterministic screen change occurs on raw threshold crossing | B-05 |
| C-04 | Create 240 fps test procedure | Camera placement, repetitions, frame counting and percentile calculation documented | C-03 |
| C-05 | Run Gate A on both phones | Raw logs, video-derived data and bottleneck analysis committed to test report | C-04 |

### Epic D — Calibration and swing detection

| ID | Task | Output / definition of done | Depends on |
| --- | --- | --- | --- |
| D-01 | Implement neutral-pose calibration | Both devices produce common axes and bias values; invalid calibration is rejected | B-05 |
| D-02 | Build labeled capture workflow | Tester records swing type, handedness and outcome alongside raw motion | C-01, D-01 |
| D-03 | Capture baseline dataset | At least 100 real swings per phone plus 20 minutes of idle/normal handling | D-02 |
| D-04 | Implement early-swing detector | Offline replay and live path produce identical events | D-03 |
| D-05 | Tune per-device calibration parameters | Target accuracy and false-positive metrics pass without hard-coded model names in gameplay | D-04 |
| D-06 | Derive normalized shot intent | Detector emits timing, power, direction, racket angle and confidence | D-05 |

### Epic E — Gameplay vertical slice

| ID | Task | Output / definition of done | Depends on |
| --- | --- | --- | --- |
| E-01 | Implement fixed-step match state machine | Serve, rally, point, game-over, pause and rematch are deterministic | A-02 |
| E-02 | Implement automatic player positioning | Player arrives near predicted shuttle location without motion input | E-01 |
| E-03 | Implement shuttle model and hit timing | Early/on-time/late/miss outcomes are visible and tunable | E-02, D-06 |
| E-04 | Map shot intent to four outcomes | Smash, clear, drop and lift are reproducibly distinguishable | E-03 |
| E-05 | Add computer opponent | At least one difficulty completes a scored match | E-03 |
| E-06 | Add audiovisual immediate feedback | Hit response begins on the detector event and is latency-instrumented | E-03 |
| E-07 | Implement rally scoring and rematch | Adjustable target score and complete match loop | E-01 |

### Epic F — Safety, resilience and release

| ID | Task | Output / definition of done | Depends on |
| --- | --- | --- | --- |
| F-01 | Add wrist-strap and clear-space confirmation | Required before calibration; wording appears on host and phones | B-03 |
| F-02 | Add slow-swing onboarding | First session teaches controlled motion and confirms detection | D-06 |
| F-03 | Run soak and network-degradation tests | Ten-minute stream and ten-match tests meet packet/session targets | B-06, E-07 |
| F-04 | Export and smoke-test three desktop platforms | Same protocol and match behavior on Windows, macOS and Linux | E-07 |
| F-05 | Write player setup and troubleshooting guide | New tester reaches a rally in under one minute without developer help | F-04 |
| F-06 | Run Gate B playtests | Results, observations and go/change/stop decision recorded | F-05 |

## 10. Test strategy

### Automated tests

- Protocol encoding, decoding, truncation, wrong version and invalid values.
- Clock-offset calculation with simulated asymmetric delay and drift.
- Sequence wraparound, duplicate, reorder, loss and stale-packet handling.
- Calibration transforms against recorded fixtures.
- Detector replay against labeled sessions.
- Match state, scoring and fixed-step determinism.
- Reconnect preserving player assignment.

### Hardware-in-the-loop tests

- iPhone only, Pixel only and both simultaneously.
- Host on Ethernet with phones on 5/6 GHz Wi-Fi.
- Host also on Wi-Fi to quantify the two-wireless-hop penalty.
- Screen refresh at 60, 120 and 144 Hz where supported.
- Foreground/background transition, screen lock, Wi-Fi interruption and app restart.
- Low battery and thermal stress after repeated matches.

### Required reports

1. **Transport report:** rate, loss, reorder, jitter, RTT and sample age for each phone.
2. **End-to-end latency report:** median, p95 and p99 from swing start to first visible response.
3. **Detector report:** precision/recall by device, player and shot type; false positives during idle handling.
4. **Playtest report:** setup time, control failures, safety observations and rematch intent.

## 11. Observability and diagnostics

Every test session receives a unique ID. Logs must include:

- App, OS, device and protocol versions.
- Sensor-requested and actual sampling rates.
- Packet sequence, sensor time, arrival time and computed age.
- RTT, estimated clock offset and drift.
- Calibration values.
- Detector inputs, trigger, confidence and final shot intent.
- Game timing result and simulation tick.
- Frame time and a visible latency-test marker.
- Disconnect, pause, reconnect and foreground transitions.

Raw motion logging is opt-in outside engineering builds. Logs must never contain personal account data, audio or video.

## 12. Principal risks and responses

| Risk | Early indicator | Response / decision |
| --- | --- | --- |
| Sensor-to-screen latency misses target | Gate A fails on one or both phones | Attribute time by stage; reduce filtering/buffering; validate display mode; only then assess phone-side prediction or hardware |
| iOS and Android axes/rates differ | Same swing produces inconsistent features | Normalize units/coordinates; store actual rate; maintain device calibration profiles outside gameplay |
| Wi-Fi contention creates spikes | p99 sample age rises while median stays low | Ethernet host, clean 5/6 GHz channel, stale discard and predictive early trigger |
| UDP packets are blocked by guest Wi-Fi isolation | Pairing succeeds visually but no bidirectional traffic | Detect and explain client isolation; support a private router/hotspot test setup; consider WebRTC later |
| QR contains an unreachable host address | Multi-adapter host selects VPN or wrong NIC | Show candidate interfaces and let the user choose; validate with handshake before calibration |
| Swing rules overfit one person | Accuracy falls for a second tester | Dataset must cover both hands, players, slow/fast swings and normal handling |
| TV expansion compromises latency | TV mode adds display processing | Require game/low-latency mode and re-run the full Gate A test on every target class |
| Scope expands before fun is proven | Packaging/content work begins before Gate B | Enforce gate policy and keep deferred items out of active sprint backlog |

## 13. First sprint: start here

The first sprint is complete when either phone can move a live graph on the host through the real protocol and the log proves sample timing. Do not implement badminton gameplay during this sprint.

### Day 1

- [ ] Confirm toolchain and pin versions.
- [ ] Create the repository structure and three runnable application shells.
- [ ] Commit ADR-001 through ADR-009.

### Day 2

- [ ] Write protocol v0 with units, byte order and packet-size limits.
- [ ] Create golden packets and codec tests.
- [ ] Implement host UDP listener and synthetic packet generator.

### Days 3–4

- [ ] Implement iOS sensor capture and `MOTION` encoding.
- [ ] Display rate, sequence loss and sample age on the host.
- [ ] Persist the first structured iOS session log.

### Days 5–6

- [ ] Implement Android sensor capture and the same protocol.
- [ ] Run both phones simultaneously for 10 minutes.
- [ ] Fix protocol or ingest discrepancies until golden tests and stream targets pass.

### Days 7–8

- [ ] Add QR pairing, player assignment and clock synchronization.
- [ ] Add heartbeat, foreground pause and reconnect.
- [ ] Freeze protocol v1 for the latency feasibility test.

### Sprint review evidence

- Host screenshot showing both devices and live motion graphs.
- Ten-minute logs from each phone and a simultaneous run.
- Table of actual sensor Hz, packet loss, RTT, jitter and sample-age percentiles.
- List of unresolved issues with owner and next action.
- Gate A test date and named test procedure.

## 14. Definition of Release 1 done

Release 1 is done only when all of the following are true:

- Both specified phones pair in under one minute and reconnect without ending a match.
- Measured latency, packet reliability and detector accuracy meet the PRD targets on the reference setup.
- One-player and two-player matches can be completed and rematched.
- The four intended shot outcomes are usable without requiring maximum-force swings.
- Disconnects pause play and all required safety prompts are present.
- Windows, macOS and Linux desktop builds pass the release smoke test.
- Telemetry can diagnose a failed swing without reproducing it live.
- Gate B playtest records positive rematch intent from both players.
- Browser/TV expansion has a documented go/no-go decision based on evidence rather than preference.
