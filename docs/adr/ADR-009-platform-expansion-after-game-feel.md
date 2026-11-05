# ADR-009: Keep browser and TV delivery behind the game-feel gate

## Context

Packaging for browsers and TV platforms would consume effort before latency,
swing reliability and replay intent are proven.

## Decision

Do not implement browser or TV hosts until Gate B validates game feel and Gate C
selects the next target from measured user and performance needs.

## Consequences

The project concentrates on its highest-risk interaction and avoids premature
distribution work. Early testers need a desktop host, and later expansion may
require a replacement transport such as WebRTC plus target-specific UX work.

## Status

Accepted

## Date

2026-11-06
