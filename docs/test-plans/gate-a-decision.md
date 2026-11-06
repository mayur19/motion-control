# Gate A latency decision

**Status:** BLOCKED — no physical two-phone latency measurements yet  
**Ticket:** TMB-025

No Gate A decision is selected. Synthetic tests, simulator builds and software
timestamps cannot replace the required 240 FPS measurements from both reference
phones. M2 tickets remain blocked until this record selects exactly one outcome.

## Required inputs

- Completed Ethernet and Wi-Fi M1 soak report with raw logs (TMB-022).
- At least 30 valid 240 FPS takes and matching stimulus events per phone
  (TMB-024).
- Per-phone median, p95 and p99 versus targets: median `< 50 ms`, p99 `< 80 ms`.
- Setup metadata, raw artifact checksums, exclusions and uncertainty.

## Attribution worksheet

| Stage | iPhone evidence | Pixel evidence | Finding/remediation |
| --- | --- | --- | --- |
| Sensor sampling | _pending_ | _pending_ | _pending_ |
| Phone processing/queue | _pending_ | _pending_ | _pending_ |
| Network/clock adjustment | _pending_ | _pending_ | _pending_ |
| Host threshold/simulation | _pending_ | _pending_ | _pending_ |
| Frame scheduling/display | _pending_ | _pending_ | _pending_ |

## Decision rule

- `GO`: both phones meet both PRD targets with valid evidence.
- `REMEDIATE AND RETEST`: a bounded, evidence-attributed change has a named
  owner, expected effect and TMB-024 retest condition.
- `STOP/REDESIGN`: targets are missed without a credible bounded remediation,
  or the phone-controller architecture is not viable.

Custom hardware and phone-side early detection may be investigated only if
measurements identify a relevant bottleneck; neither is adopted speculatively.

**Decision:** PENDING — do not infer `GO`.
