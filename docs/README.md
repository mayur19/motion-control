# Documentation index

New here? Read the [project README](../README.md), then
[Getting started](getting-started.md) and the
[architecture overview](architecture.md).

## Overview and planning

| Document | What it covers |
| --- | --- |
| [Product requirements (PRD)](../Two-Phone%20Motion%20Badminton%20PRD.md) | Goals, success measures, requirements, safety, risks |
| [Architecture and delivery plan](../Two-Phone%20Motion%20Badminton%20Architecture%20and%20Delivery%20Plan.md) | Original design, component boundaries, milestones, gates, test strategy |
| [Architecture overview](architecture.md) | Current system map, protocol summary, pipeline, source layout |
| [Roadmap](roadmap.md) | Phase status, next steps, known issues, future ideas |
| [Research notes](research.md) | Measured findings, methods, open questions, lessons |
| [Implementation tickets](../implementation-tickets/README.md) | 62 ordered tickets with acceptance criteria and implementation logs |
| [Architecture decision records](adr/README.md) | ADR-001 to ADR-011 |

## Building and running

| Document | What it covers |
| --- | --- |
| [Getting started](getting-started.md) | Clone → host → controller → pairing → tests → troubleshooting |
| [Development environment](development.md) | Pinned toolchain and installation |
| [Host app](../apps/host-godot/README.md) · [iOS app](../apps/controller-ios/README.md) · [Android app](../apps/controller-android/README.md) | Per-app build notes |
| [Contributing](../CONTRIBUTING.md) | Workflow, testing, evidence and data rules |

## Protocol and networking

| Document | What it covers |
| --- | --- |
| [Protocol v1 specification](../protocol/spec.md) | Normative byte layout for all eight messages |
| [Golden vectors](../protocol/golden-vectors/README.md) | Cross-language encode/decode fixtures |
| [Pairing](pairing.md) | QR payload, session rotation, interface selection |
| [Clock synchronization](clock-synchronization.md) | Four-timestamp estimator, drift, adjusted sample time |
| [Heartbeat and reconnect](reconnect.md) | Connection states, reservation window, rejoin |
| [Session log schema](log-schema.md) | JSONL records and events |

## Motion, detection and data

| Document | What it covers |
| --- | --- |
| [Racket coordinate system](racket-coordinate-system.md) | Device frame, neutral grip, handedness, transforms, acceptance ranges |
| [Motion preprocessing](motion-preprocessing.md) | Low-pass filter, measured delay, gap handling |
| [Swing detection](swing-detection.md) | `early_rise` rule, event fields, evidence, open questions |
| [Capture format](capture-format.md) | Immutable raw captures and append-only labels |
| [Detector evaluation](detector-evaluation.md) | Tune/held-out workflow, count-based metrics and their limits |
| [External dataset evaluation](external-dataset-evaluation.md) | Public badminton datasets: domain gaps, licensing, recommendation |
| [External dataset sources](external-dataset-sources.json) | Machine-readable source manifest |

## Test plans and reports

| Document | What it covers |
| --- | --- |
| [End-to-end latency](test-plans/end-to-end-latency.md) | 240 fps camera procedure |
| [Gate A decision](test-plans/gate-a-decision.md) | Latency feasibility result and `GO` decision |
| [M1 soak report](test-plans/m1-soak-report.md) | Two-phone streaming results and the AWDL finding |
| [TMB-030 dataset capture plan](test-plans/tmb-030-dataset-capture-plan.md) | Sessions, labels, tune/held-out split |
| [`evidence/`](evidence/) | Raw evidence per ticket: logs, plots, reports, checksums |

`handoffs/` holds prompts used to hand work between coding agents; they are
historical and not user documentation.
