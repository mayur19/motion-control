# Architecture decision records

Accepted architecture decisions are immutable records of why the project chose
a direction. If evidence changes a decision, add a new ADR that supersedes the
old record instead of rewriting its history.

| ID | Decision | Status |
| --- | --- | --- |
| [ADR-001](ADR-001-native-godot-desktop-host.md) | Native Godot desktop is the first display host | Accepted |
| [ADR-002](ADR-002-native-swift-and-kotlin-controllers.md) | Swift and Kotlin controllers remain native | Accepted |
| [ADR-003](ADR-003-unicast-udp-motion-transport.md) | Use unicast UDP for motion samples | Accepted |
| [ADR-004](ADR-004-versioned-binary-protocol.md) | Use a fixed, versioned binary packet format | Accepted |
| [ADR-005](ADR-005-host-generated-qr-pairing.md) | Pair with a host-generated QR code | Accepted |
| [ADR-006](ADR-006-host-side-swing-detection.md) | Detect swings on the host for Release 1 | Accepted |
| [ADR-007](ADR-007-fixed-timestep-simulation.md) | Run game simulation on a fixed timestep | Accepted |
| [ADR-008](ADR-008-raw-motion-and-event-logs.md) | Store raw motion and derived events in test logs | Accepted |
| [ADR-009](ADR-009-platform-expansion-after-game-feel.md) | Keep browser/TV delivery behind the game-feel gate | Accepted |

Each record uses the same Context, Decision, Consequences, Status and Date
fields. See the [architecture plan](../../Two-Phone%20Motion%20Badminton%20Architecture%20and%20Delivery%20Plan.md)
for component boundaries and delivery gates.
