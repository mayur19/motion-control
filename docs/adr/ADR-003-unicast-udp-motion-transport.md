# ADR-003: Use unicast UDP for motion samples

## Context

Motion samples expire quickly: delayed retransmission is less useful than the
next fresh sample. The target setup is a trusted local network with one host and
one or two paired controllers.

## Decision

Send motion samples as individual unicast UDP datagrams to the paired host.
Pairing and configuration messages use bounded retries and acknowledgements as
needed, but motion samples are never retransmitted.

## Consequences

The transport avoids head-of-line blocking and exposes packet age directly.
Packets may be lost, duplicated or reordered, so sequence validation, stale
discard, metrics and reconnect behavior must be implemented by the application.

## Status

Accepted

## Date

2026-11-06
