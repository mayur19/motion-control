# ADR-010: Carry handedness in the calibration packet

## Context

TMB-026 requires an explicit right- or left-hand selection so the host can
normalize motion into the common racket frame. The original protocol v1
`CALIBRATION` payload carried the neutral pose and sensor biases but omitted
handedness. Inferring a hand from inertial data is unreliable, and keeping the
selection only on the controller would make host-side replay incomplete.

## Decision

Allocate byte 53 of the existing 56-byte `CALIBRATION` payload to a required
`handedness` enum (`1` right, `2` left). Reduce the reserved tail from three
bytes to two. Preserve protocol version 1 and the packet size because Release 1
has not shipped and Swift, Kotlin, GDScript and the golden fixtures are updated
atomically.

## Consequences

Calibration records are self-contained and replayable, and the host never has
to infer handedness. Pre-TMB-027 development builds reject the new nonzero byte,
so all controller and host binaries used together must include this change.
Future protocol changes after a shipped version must use explicit versioning
rather than reallocating reserved bytes.

## Status

Accepted

## Date

2026-11-06
