# ADR-011: Treat Core Motion attitude as device-to-reference

## Context

Protocol v1 `orientation_*` is an active device-to-reference quaternion.
TMB-026 assumed Core Motion's attitude quaternion used the inverse convention
and made the iOS sensor adapter send `(-x, -y, -z, w)`. This was never checked
on hardware. TMB-027's first physical calibration showed the problem: an
upright portrait iPhone reports Core Motion pitch +90°, quaternion
`(sin 45°, 0, 0, cos 45°)`, which already rotates `+Y_D` onto vertical `+Z`.
The inversion made every correctly held phone read as pointing down, and
neutral capture always failed.

## Decision

Core Motion attitude, like Android's rotation vector, is already
device-to-reference. The iOS adapter passes it through unchanged. A unit test
pins the physical ground truth (upright portrait → shaft up), and
`docs/racket-coordinate-system.md` states the convention for both platforms.
The protocol, packet layout and golden fixtures do not change.

## Consequences

Both controllers now send orientation in the same convention, as TMB-026
intended. iOS orientation sent by builds before `414c0da` is inverted and
cannot be compared with later logs. Gate A latency evidence is unaffected,
because it used only angular speed. Any future claim about a native sensor
convention needs a physical check or a hardware-derived test before it
becomes part of the contract.

## Status

Accepted

## Date

2026-11-06
