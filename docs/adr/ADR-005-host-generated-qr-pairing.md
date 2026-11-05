# ADR-005: Pair with a host-generated QR code

## Context

Automatic discovery behaves differently across desktop and phone platforms and
can select an unreachable VPN or guest-network interface.

## Decision

The host displays a QR payload containing protocol version, selected host
address, UDP port, session identifier and a short-lived pairing secret. Phones
scan it, with a manual entry fallback added later.

## Consequences

Pairing is explicit and avoids discovery dependencies during feasibility work.
It requires camera permission, a visible host display and careful handling of
expired secrets and unreachable interface choices.

## Status

Accepted

## Date

2026-11-06
