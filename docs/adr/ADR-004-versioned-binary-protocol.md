# ADR-004: Use a fixed, versioned binary packet format

## Context

Swift, Kotlin and GDScript must exchange high-rate motion samples with minimal
allocation and identical field interpretation.

## Decision

Define a network-byte-order binary protocol with a fixed common header, bounded
payloads, explicit versions and cross-language golden vectors.

## Consequences

Packet size and parsing cost are predictable, and byte-for-byte compatibility
can be tested. Binary data is less inspectable than text and schema evolution
requires deliberate versioning, strict validation and fixture maintenance.

## Status

Accepted

## Date

2026-11-06
