# Implementation Tickets

This folder is the executable delivery backlog for the Two-Phone Motion Badminton project. Each ticket is a standalone work item with status, labels, estimate, dependencies, implementation steps, acceptance criteria and required evidence.

The source product and architecture documents remain:

- [Product requirements](../Two-Phone%20Motion%20Badminton%20PRD.md)
- [Architecture and delivery plan](../Two-Phone%20Motion%20Badminton%20Architecture%20and%20Delivery%20Plan.md)

## Execution rules

- Execute tickets in numeric order unless a ticket explicitly allows parallel work.
- Keep no more than two implementation tickets in progress.
- A ticket becomes Ready only after every dependency is Done.
- A ticket becomes Done only after its acceptance criteria pass and its evidence is saved.
- Do not start work beyond Gate A or Gate B until the gate ticket records a GO decision.
- Start with TMB-001 only.

## Phase index

### M0 — Foundation

Three runnable application shells and protocol v1.

- [TMB-001 — Verify and pin the development toolchain](TMB-001-verify-and-pin-the-development-toolchain.md)
- [TMB-002 — Create the repository structure and project conventions](TMB-002-create-the-repository-structure-and-project-conventions.md)
- [TMB-003 — Commit the initial architecture decision records](TMB-003-commit-the-initial-architecture-decision-records.md)
- [TMB-004 — Create the Godot host application shell](TMB-004-create-the-godot-host-application-shell.md)
- [TMB-005 — Create the iOS controller application shell](TMB-005-create-the-ios-controller-application-shell.md)
- [TMB-006 — Create the Android controller application shell](TMB-006-create-the-android-controller-application-shell.md)
- [TMB-007 — Specify protocol v1](TMB-007-specify-protocol-v1.md)
- [TMB-008 — Create protocol golden vectors and negative fixtures](TMB-008-create-protocol-golden-vectors-and-negative-fixtures.md)
- [TMB-009 — Implement and verify the three protocol codecs](TMB-009-implement-and-verify-the-three-protocol-codecs.md)

### M1 — Instrumented vertical slice

Both phones stream measurable motion to the host.

- [TMB-010 — Build a synthetic motion-packet generator](TMB-010-build-a-synthetic-motion-packet-generator.md)
- [TMB-011 — Implement host UDP ingest and session-independent metrics](TMB-011-implement-host-udp-ingest-and-session-independent-metrics.md)
- [TMB-012 — Add structured host session logging](TMB-012-add-structured-host-session-logging.md)
- [TMB-013 — Add the host networking diagnostics HUD](TMB-013-add-the-host-networking-diagnostics-hud.md)
- [TMB-014 — Implement iOS sensor sampling](TMB-014-implement-ios-sensor-sampling.md)
- [TMB-015 — Stream iOS motion packets to the host](TMB-015-stream-ios-motion-packets-to-the-host.md)
- [TMB-016 — Implement Android sensor sampling](TMB-016-implement-android-sensor-sampling.md)
- [TMB-017 — Stream Android motion packets to the host](TMB-017-stream-android-motion-packets-to-the-host.md)
- [TMB-018 — Implement host session creation and QR payload](TMB-018-implement-host-session-creation-and-qr-payload.md)
- [TMB-019 — Implement QR join and handshake on both controllers](TMB-019-implement-qr-join-and-handshake-on-both-controllers.md)
- [TMB-020 — Implement monotonic clock synchronization](TMB-020-implement-monotonic-clock-synchronization.md)
- [TMB-021 — Implement heartbeat, disconnect and reconnect](TMB-021-implement-heartbeat-disconnect-and-reconnect.md)
- [TMB-022 — Run the M1 simultaneous-controller soak test](TMB-022-run-the-m1-simultaneous-controller-soak-test.md)

### Gate A — Phone feasibility

Measured end-to-end latency decision.

- [TMB-023 — Build the raw-input latency stimulus](TMB-023-build-the-raw-input-latency-stimulus.md)
- [TMB-024 — Document and execute the 240 FPS latency test](TMB-024-document-and-execute-the-240-fps-latency-test.md)
- [TMB-025 — Gate A decision: continue, remediate or stop](TMB-025-gate-a-decision-continue-remediate-or-stop.md)

### M2 — Swing laboratory

Calibrated and measured swing detection.

- [TMB-026 — Define the common racket coordinate system](TMB-026-define-the-common-racket-coordinate-system.md)
- [TMB-027 — Implement slow-swing calibration on both controllers](TMB-027-implement-slow-swing-calibration-on-both-controllers.md)
- [TMB-028 — Implement host calibration application and verification](TMB-028-implement-host-calibration-application-and-verification.md)
- [TMB-029 — Build labeled motion capture and replay tools](TMB-029-build-labeled-motion-capture-and-replay-tools.md)
- [TMB-030 — Capture the baseline motion dataset](TMB-030-capture-the-baseline-motion-dataset.md)
- [TMB-031 — Implement motion preprocessing](TMB-031-implement-motion-preprocessing.md)
- [TMB-032 — Implement the early-swing detector](TMB-032-implement-the-early-swing-detector.md)
- [TMB-033 — Build detector evaluation and tuning reports](TMB-033-build-detector-evaluation-and-tuning-reports.md)
- [TMB-034 — Derive normalized shot intent](TMB-034-derive-normalized-shot-intent.md)
- [TMB-035 — Gate the swing laboratory results](TMB-035-gate-the-swing-laboratory-results.md)

### M3 — One-player rally

Complete practice match against an AI opponent.

- [TMB-036 — Implement the fixed-step match state machine](TMB-036-implement-the-fixed-step-match-state-machine.md)
- [TMB-037 — Implement the initial court and shuttle simulation](TMB-037-implement-the-initial-court-and-shuttle-simulation.md)
- [TMB-038 — Implement automatic player positioning](TMB-038-implement-automatic-player-positioning.md)
- [TMB-039 — Map swing trigger and timing to a shuttle hit](TMB-039-map-swing-trigger-and-timing-to-a-shuttle-hit.md)
- [TMB-040 — Add immediate audiovisual hit feedback](TMB-040-add-immediate-audiovisual-hit-feedback.md)
- [TMB-041 — Implement the computer opponent](TMB-041-implement-the-computer-opponent.md)
- [TMB-042 — Implement scoring, serve rotation and rematch](TMB-042-implement-scoring-serve-rotation-and-rematch.md)
- [TMB-043 — Add gameplay tuning controls and configuration snapshots](TMB-043-add-gameplay-tuning-controls-and-configuration-snapshots.md)
- [TMB-044 — Validate the one-player vertical slice](TMB-044-validate-the-one-player-vertical-slice.md)

### M4 — Two-player match

Safe and resilient two-player match loop.

- [TMB-045 — Integrate two simultaneous players into gameplay](TMB-045-integrate-two-simultaneous-players-into-gameplay.md)
- [TMB-046 — Implement smash and clear outcomes](TMB-046-implement-smash-and-clear-outcomes.md)
- [TMB-047 — Implement drop and underhand-lift outcomes](TMB-047-implement-drop-and-underhand-lift-outcomes.md)
- [TMB-048 — Add safety confirmation and session interlocks](TMB-048-add-safety-confirmation-and-session-interlocks.md)
- [TMB-049 — Harden reconnect during an active match](TMB-049-harden-reconnect-during-an-active-match.md)
- [TMB-050 — Execute network degradation and stale-input tests](TMB-050-execute-network-degradation-and-stale-input-tests.md)
- [TMB-051 — Run the ten-match resilience test](TMB-051-run-the-ten-match-resilience-test.md)
- [TMB-052 — Conduct four-shot usability verification](TMB-052-conduct-four-shot-usability-verification.md)

### Gate B — Game feel

Playtest-based go/change/stop decision.

- [TMB-053 — Run the structured game-feel playtest](TMB-053-run-the-structured-game-feel-playtest.md)
- [TMB-054 — Gate B decision: continue, redesign or stop](TMB-054-gate-b-decision-continue-redesign-or-stop.md)

### M5 — Desktop release candidate

Tested Windows, macOS and Linux builds.

- [TMB-055 — Create repeatable Windows, macOS and Linux exports](TMB-055-create-repeatable-windows-macos-and-linux-exports.md)
- [TMB-056 — Add automated build and test workflows](TMB-056-add-automated-build-and-test-workflows.md)
- [TMB-057 — Run desktop portability smoke tests](TMB-057-run-desktop-portability-smoke-tests.md)
- [TMB-058 — Re-run latency and packet tests on the release candidate](TMB-058-re-run-latency-and-packet-tests-on-the-release-candidate.md)
- [TMB-059 — Write player setup and troubleshooting documentation](TMB-059-write-player-setup-and-troubleshooting-documentation.md)
- [TMB-060 — Complete the Release 1 acceptance test](TMB-060-complete-the-release-1-acceptance-test.md)
- [TMB-061 — Tag and archive the desktop Release 1 candidate](TMB-061-tag-and-archive-the-desktop-release-1-candidate.md)

### Gate C — Platform expansion

Evidence-based next-platform decision.

- [TMB-062 — Decide the next display-host target](TMB-062-decide-the-next-display-host-target.md)

## Workflow

`Backlog → Ready → In Progress → Review → Done`

When implementation begins, update the **Status** field inside the relevant ticket. Architecture or product changes discovered during execution must be reflected in an ADR, the architecture plan or the PRD as appropriate.

