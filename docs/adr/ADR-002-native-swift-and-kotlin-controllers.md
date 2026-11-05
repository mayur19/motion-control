# ADR-002: Swift and Kotlin controllers remain native

## Context

The phone apps need high-rate sensor access, monotonic timestamps, explicit
foreground behavior and platform-specific network tuning.

## Decision

Implement the iOS controller in Swift and the Android controller in Kotlin,
with matching state names and behavior but no shared cross-platform UI runtime.

## Consequences

Each controller can use its platform sensor and lifecycle APIs directly. The
cost is two application implementations and the risk of behavioral drift, so
shared protocol fixtures and mirrored state-transition tests are mandatory.

## Status

Accepted

## Date

2026-11-06
