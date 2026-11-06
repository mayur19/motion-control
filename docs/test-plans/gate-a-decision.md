# Gate A latency decision

**Status:** FINAL `GO` — project-owner decision, 2026-11-06

**Ticket:** TMB-025

Gate A is closed with a final `GO`. M2 may proceed. The owner accepts a
stage-attributed threshold-to-visible bound for the Galaxy and a same-setup
physical parity check on the iPhone in place of separate 30-take
motion-onset-to-visible percentile sets.

## Required inputs

- Completed Ethernet and Wi-Fi M1 soak report with raw logs (TMB-022).
- Galaxy threshold-to-render timestamps for 41 triggers and 27 camera-correlated
  display transitions from `IMG_9712.MOV` (TMB-024).
- Conservative comparison with the targets: median `< 50 ms`, p99 `< 80 ms`.
- Owner-observed iPhone physical parity on the same setup.

## Attribution worksheet

| Stage | iPhone evidence | Galaxy evidence | Finding/remediation |
| --- | --- | --- | --- |
| Sensor sampling | Physical parity check accepted by owner | Adjusted sensor timestamps on 41 triggers | No feasibility blocker observed |
| Phone processing/queue | Equivalent physical response accepted by owner | Included in threshold-to-render timing | No remediation |
| Network/clock adjustment | TMB-022: loss + late below 0.2% | TMB-022 plus correlated event log | No remediation; keep AWDL off |
| Host threshold/simulation | Same host path | Median sample-to-render 30.1 ms; p95 42.6 ms; p99/max 54.1 ms | Meets stage budget |
| Frame scheduling/display | Same physical host display | 27 correlated transitions; render/video phase spread 11.95 ms | Conservative 17.5 ms display allowance |

## Accepted measurement basis

The second Galaxy recording corrected the original camera-angle defect. Its
gradual hand acceleration made first-visible-motion an unsuitable start
boundary, so the accepted feasibility boundary is the first logged sample that
crosses the raw 3.5 rad/s threshold. This separates controller/network/render
latency from gesture acceleration and detector tuning, which belongs to M2.

For all 41 Galaxy triggers, adjusted sensor sample to host render marker was:

- median 30.1 ms;
- p95 42.6 ms;
- p99/max 54.1 ms.

Twenty-seven display transitions in the 240 FPS video align with the matching
render events. Their render-to-video phase spread is 11.95 ms. Applying a
conservative 17.5 ms allowance for one 120 Hz refresh, panel response and one
camera-frame quantization interval gives an all-trigger upper bound of:

- median threshold-to-visible latency at most 47.6 ms;
- p99/max threshold-to-visible latency at most 71.6 ms.

Both bounds pass the PRD targets. The project owner immediately exercised the
iPhone on the same physical setup, observed behavior equivalent to Android and
explicitly accepts that parity check as final iPhone feasibility evidence. No
separate retained iPhone percentile set exists; this is an owner-approved Gate
A evidence exception, not an inferred measurement.

Artifacts:

- `IMG_9712.MOV`: SHA-256
  `3e3bba41605ba6e04664bd7ffd954ade81012aca6923fcf441a628e26522fd74`.
- Session `41CEF61F73595D9B`, 41 selected threshold events: canonical JSONL
  subset SHA-256
  `c0cbc223f409ccfc8a55dee904467a34e430c58daf9a20f0ca61b0cce5bc0f58`.

## Decision rule

- `GO`: both phones meet both PRD targets with valid evidence.
- `REMEDIATE AND RETEST`: a bounded, evidence-attributed change has a named
  owner, expected effect and TMB-024 retest condition.
- `STOP/REDESIGN`: targets are missed without a credible bounded remediation,
  or the phone-controller architecture is not viable.

Custom hardware and phone-side early detection may be investigated only if
measurements identify a relevant bottleneck; neither is adopted speculatively.

## Decision

**Final `GO` (project owner, 2026-11-06).** The phone-controller architecture
is feasible for M2. Custom hardware and phone-side early detection are not
needed. Future release-candidate and target-display tests may create new
remediation work, but they do not make this recorded decision provisional.
