# TMB-007 — Specify protocol v1

**Status:** Done  
**Labels:** `protocol`, `architecture`  
**Estimate:** 1 day  
**Dependencies:** TMB-003

### Implementation steps

1. Define common packet header, byte order, numeric types, size limits and compatibility rules.
2. Define `HELLO`, `WELCOME`, `PING`, `PONG`, `MOTION`, `CALIBRATION`, `STATUS` and `GOODBYE` payloads.
3. Fix all motion units: acceleration in m/s², angular velocity in rad/s, timestamps in monotonic nanoseconds and orientation as a normalized quaternion.
4. Define session, controller, player, sequence and protocol-version semantics.
5. Define malformed, unknown-version, duplicate, reordered and stale-packet handling.
6. Add a worked byte-level example for a `MOTION` packet.

### Acceptance criteria

- A Swift, Kotlin or GDScript developer can implement a codec without an undocumented assumption.
- Every field has offset/order, type, units and validity constraints.
- The maximum packet fits comfortably within a single LAN datagram without fragmentation.

### Evidence

- `protocol/spec.md`
- Reviewed example packet

### Implementation log

- 2026-11-06: Froze protocol v1 with a 28-byte header, eight bounded payloads,
  big-endian numeric encoding and an 80-byte worked `MOTION` example.
- 2026-11-06: Defined identity, sequencing, retry, duplicate, reorder, stale,
  compatibility and deterministic rejection rules.
- 2026-11-06: Verified the worked hexadecimal example decodes to exactly 80
  bytes and every required message section and unit is present.


