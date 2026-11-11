# Roadmap

Last updated: 2026-11-11. The authoritative per-task state is the **Status**
field inside each ticket in [`implementation-tickets/`](../implementation-tickets/README.md);
this page is the readable summary. If the two disagree, the ticket wins.

## Principles

1. **Measure the riskiest thing first.** Latency decided whether phones could be
   controllers at all, so it was measured before anything else. Swing-detection
   accuracy decides whether the game can be fun, so gameplay waits for it.
2. **Gates, not momentum.** Each phase ends at a gate with written pass
   criteria. A missed gate produces a measured design decision (remediate,
   redesign or stop), never automatic continuation.
3. **Evidence is honest.** Estimates, synthetic tests and owner-approved
   exceptions are labeled as such in ticket logs and reports.
4. **Small, deferred scope.** Browser/TV hosts, ML in the runtime, online play
   and production art stay out until the evidence asks for them.

## Phase overview

```text
 M0 ─ M1 ─ [Gate A] ─ M2 ─ [M2 gate] ─ M3 ─ M4 ─ [Gate B] ─ M5 ─ [Gate C]
 done  done   GO     ◀ now     next      ───── gameplay ─────  release  expansion
```

| Phase | Tickets | Goal | Exit criteria | Status |
| --- | --- | --- | --- | --- |
| **M0 Foundation** | TMB-001–009 | Pinned toolchain, three app shells, protocol v1 and codecs | All apps build; Swift, Kotlin and GDScript pass the same golden vectors | ✅ Done |
| **M1 Instrumented vertical slice** | TMB-010–022 | Both phones stream measurable motion to the host | ≥ 100 Hz per phone; loss + late < 1%; reconnect works; complete timing logs | ✅ Done ¹ |
| **Gate A Phone feasibility** | TMB-023–025 | Is swing-to-screen latency good enough? | Median < 50 ms, p99 < 80 ms | ✅ **GO**, 2026-11-06 ² |
| **M2 Swing laboratory** | TMB-026–035 | Calibrated, measured swing detection and shot intent | ≥ 95% recall and < 1 false swing / 10 min on held-out data, both phones | 🔄 In progress |
| **M3 One-player rally** | TMB-036–044 | Practice match vs a computer opponent | 5-minute match without debug intervention; stable frame rate | ⏳ Blocked on M2 gate |
| **M4 Two-player match** | TMB-045–052 | Two controllers, four shot outcomes, safety, resilience | 10 consecutive matches without session failure; shots distinguishable in blind test | ⏳ |
| **Gate B Game feel** | TMB-053–054 | Is it fun? | Both players ask for a rematch after five matches; no critical safety issue | ⏳ |
| **M5 Desktop release candidate** | TMB-055–061 | Windows, macOS, Linux builds; CI; player guide | Smoke tests on all targets; latency re-run; release checklist | ⏳ |
| **Gate C Platform expansion** | TMB-062 | Which display host is next? | Decision from measured user environment (browser vs Android TV) | ⏳ |

¹ TMB-022 soak passed with a Wi-Fi host and AWDL disabled. The Ethernet-host
run is not possible on the current test machine and remains open.
² Owner decision with a recorded evidence exception: the Galaxy was measured
with a 240 fps camera; the iPhone was accepted on a same-setup physical parity
check. See [Gate A](test-plans/gate-a-decision.md).

## Done so far

| Area | What exists | Docs |
| --- | --- | --- |
| Protocol | Frozen v1 binary protocol, 8 message types, golden vectors, three codecs | [spec](../protocol/spec.md) |
| Pairing | QR + manual code, 120 s expiring secret, interface selection, rotation | [pairing](pairing.md) |
| Clock sync | Four-timestamp estimator, low-RTT quartile median, drift in ppm | [clock sync](clock-synchronization.md) |
| Resilience | 500 ms heartbeat, Connected/Degraded/Paused/Disconnected, 30 s seat reservation, rejoin | [reconnect](reconnect.md) |
| Diagnostics | HUD (rate, loss, jitter, sample age, RTT), JSONL logs, soak telemetry, AWDL warning | [log schema](log-schema.md) |
| Latency | Raw-threshold flash stimulus and 240 fps frame-counting tool | [latency plan](test-plans/end-to-end-latency.md) |
| Calibration | Neutral grip + slow swing on both phones, both hands; host normalizer to a common racket frame | [racket frame](racket-coordinate-system.md) |
| Data | F6 labeled capture, immutable raw + checksum, append-only labels, headless replay | [capture format](capture-format.md) |
| Detection | Causal preprocessing, `early_rise` detector, evaluation/tuning reports | [preprocessing](motion-preprocessing.md), [detection](swing-detection.md), [evaluation](detector-evaluation.md) |

## Now: finishing the swing laboratory (M2)

| Ticket | Work | State |
| --- | --- | --- |
| TMB-030 | Baseline dataset: per phone ≥ 100 swings and ≥ 20 non-swing minutes, session-level tune/held-out split | iPhone tune sessions S1–S3, N1–N3 recorded (90 swings, 19.8 min). iPhone held-out S4/N4 and all Galaxy sessions pending |
| TMB-031 | Motion preprocessing | Review. 25 Hz cutoff kept for iPhone; re-check on Galaxy's 250 Hz stream |
| TMB-032 | `early_rise` detector | Review. iPhone tune defaults selected (9.5 rad/s onset, 700 ms refractory) |
| TMB-033 | Evaluation and tuning reports | Tooling done; held-out and cross-device evaluation pending |
| TMB-034 | Normalized shot intent: timing, power, direction, racket angle, confidence | Blocked on TMB-033 |
| TMB-035 | M2 gate decision | Blocked |

Next concrete steps, in order:

1. Record iPhone held-out sessions **S4 and N4** with exact swing counts, then
   evaluate them **once** with the frozen configuration
   (`--split heldout --confirm-heldout`).
2. Record Galaxy sessions S1–S4 and N1–N4 when the borrowed phone is available.
   Re-check the preprocessing cutoff and detector thresholds on Galaxy tune data
   only.
3. Run the live idle/handling acceptance check for false triggers.
4. Collect at least one left-handed session per phone, and a second player if
   one is available.
5. Resolve the **backswing vs forward swing** question (see
   [research](research.md#open-research-questions)), which needs per-swing
   timing labels or annotated captures.
6. Derive shot intent (TMB-034), then hold the M2 gate (TMB-035).

## Next: gameplay (M3–M4)

Planned once the M2 gate says `GO`:

- Fixed-step (≥ 120 Hz) match state machine: serve, rally, point, game over,
  pause, rematch. Deterministic at 60, 120 and 144 Hz display rates.
- Court and shuttle simulation; automatic player positioning toward the
  predicted landing point.
- Swing trigger + timing window → shuttle hit (early, on time, late, miss).
- Immediate audiovisual feedback fired from the detector event and
  latency-instrumented.
- Computer opponent with at least one difficulty.
- Rally-point scoring, serve rotation and rematch.
- Live tuning controls with configuration snapshots.
- Two simultaneous players; smash, clear, drop and underhand lift outcomes.
- Safety: wrist-strap and clear-space confirmation, pause on disconnect,
  slow-swing onboarding.
- Network degradation, stale-input and ten-match resilience tests.

## Later: release and expansion (M5, Gate C)

- Repeatable Windows, macOS and Linux exports.
- CI: formatting, unit tests for all three codebases, golden vectors in every
  language, desktop export artifacts, retained logs for failed runs.
- Portability smoke tests and a latency/packet re-run on the release candidate.
- Player setup and troubleshooting guide (goal: a new player reaches a rally in
  under a minute without help).
- Gate C: choose the next display host from measurements. Candidates are a
  browser host (the transport is isolated so UDP can be swapped for WebRTC)
  and Android TV (requires game/low-latency display mode and a full Gate A
  re-run).

## Known issues and open items

| Item | Impact | Plan |
| --- | --- | --- |
| No Ethernet-host soak run | Two-wireless-hop penalty not quantified | Run when an Ethernet host is available |
| Android stops background traffic after ~5 s | App must stay in the foreground | Foreground service is an owner decision |
| A controller paused for invalid calibration is not told on screen | Confusing for the player | Needs a protocol/status message |
| Android physical clock-drift plot missing | Only iPhone drift is physically plotted | Record on the next Galaxy session |
| Detector tuned on one right-handed player and one phone | May not generalize | Galaxy, left-hand and second-player data (TMB-030) |
| Count-based detector metrics | Cannot attribute a trigger to a specific swing | Add per-swing timing labels |

## Ideas beyond Release 1 (not committed)

These are recorded so they are not lost. None of them is scheduled; each would
need evidence and an ADR before work starts.

- **Compact offline-trained classifier** for shot type, only if rule-based
  classification misses the accuracy gate on a varied labeled dataset.
- **Phone-side early detection or prediction**, only if a measured latency
  bottleneck calls for it.
- **WebRTC transport** for a browser host; **Android TV / Apple TV** hosts.
- **More phones**: community measurements of sensor rate and latency on other
  models, using the existing soak and latency tools.
- **Other racket sports** (tennis, squash) reusing the controller path; out of
  scope for Release 1.
- **Controller-side calibration transform** (protocol sensor flag bit 4 is
  reserved for it).
- **Automatic discovery** (mDNS) as an alternative to QR pairing.
