# Two-Phone Motion Badminton

A local multiplayer badminton game displayed by a Godot desktop host and
controlled by native iOS and Android apps. Each phone streams timestamped motion
samples over the local network; the host detects swings and runs the game.

## Repository map

| Path | Purpose |
| --- | --- |
| `apps/host-godot/` | Cross-platform Godot desktop host |
| `apps/controller-ios/` | Native Swift iPhone controller |
| `apps/controller-android/` | Native Kotlin Android controller |
| `protocol/` | Protocol specification, fixtures and compatibility assets |
| `tools/` | Packet, log-analysis and latency utilities |
| `docs/adr/` | Architecture decision records and index |
| `docs/test-plans/` | Repeatable engineering and acceptance test plans |
| `docs/playtests/` | Structured playtest plans and results |
| `implementation-tickets/` | Ordered executable delivery backlog |

## Start here

1. Read the [product requirements](Two-Phone%20Motion%20Badminton%20PRD.md)
   and [architecture plan](Two-Phone%20Motion%20Badminton%20Architecture%20and%20Delivery%20Plan.md).
2. Install the pinned toolchain using [the development guide](docs/development.md).
3. Follow the ticket order in [the implementation backlog](implementation-tickets/README.md).
4. Review accepted decisions in [the ADR index](docs/adr/README.md).

Application-specific build and run commands live in each application directory.
Protocol implementations must pass the shared golden vectors before a protocol
change can be accepted.

## Product targets

- Native Godot host for Windows, macOS and Linux.
- Native Swift and Kotlin controllers.
- Median swing-to-screen latency below 50 ms on the reference setup.
- One- and two-player matches with smash, clear, drop and lift outcomes.
- Measured packet health, deterministic gameplay and reproducible test logs.

Hardware acceptance checks may be deferred during software-only development,
but they must be completed before the corresponding latency, resilience or
release gate is accepted.
