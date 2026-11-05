# ADR-001: Native Godot desktop is the first display host

## Context

The first host must receive low-latency UDP motion, render at 60–144 Hz and run
on Windows, macOS and Linux. A browser host would add networking and scheduling
constraints before phone-controller feasibility is known.

## Decision

Build Release 1 as a native Godot 4 desktop application. Windows on the HP
Victus is the reference target, while host code remains free of Windows-only
APIs.

## Consequences

One project can serve all desktop targets and expose native UDP and frame-timing
controls. The team must maintain Godot expertise and separate platform-neutral
logic from export-specific configuration. Browser and TV distribution require
later transport and packaging work.

## Status

Accepted

## Date

2026-11-06
