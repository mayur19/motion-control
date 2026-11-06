# TMB-025 — Gate A decision: continue, remediate or stop

**Status:** Done — final `GO` (project-owner decision, 2026-11-06)

**Labels:** `gate`, `quality`, `architecture`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-024

### Implementation steps

1. Compare both phones with the PRD target: median under 50 ms and p99 under 80 ms.
2. Attribute misses to sensor sampling, phone processing, network, host processing, frame scheduling or display where evidence permits.
3. Select exactly one decision: `GO`, `REMEDIATE AND RETEST`, or `STOP/REDESIGN`.
4. If remediation is chosen, create bounded remediation tickets and repeat TMB-024.
5. Record whether custom hardware or phone-side early detection needs investigation; do not adopt either without evidence.

### Acceptance criteria

- The decision is supported by measurements from both phones.
- Any remediation has an owner, expected effect and retest condition.
- M2 tickets remain blocked unless the decision is `GO`.

### Evidence

- `docs/test-plans/gate-a-decision.md`
- Architecture/PRD update if a target or design changes

### Implementation log

- 2026-11-06: Added the decision record with required inputs, attribution table,
  exact decision rules and downstream block. No decision is selected without
  measurements from both physical phones.



### Decision record

**2026-11-06: final `GO` (project owner).** This supersedes the provisional
decision recorded earlier the same day.

Basis:
- A second Galaxy M14 5G run logged 41 raw-threshold triggers: adjusted sensor
  sample to render marker median 30.1 ms, p95 42.6 ms and p99/max 54.1 ms.
- Twenty-seven matching transitions in `IMG_9712.MOV` constrain render/display
  timing to an 11.95 ms phase spread. With a conservative 17.5 ms display and
  camera allowance, the all-trigger threshold-to-visible upper bounds are
  median 47.6 ms and p99/max 71.6 ms, passing the 50/80 ms targets.
- The accepted start boundary is raw 3.5 rad/s threshold crossing. Deliberate
  slow acceleration before that boundary is detector/game-feel work for M2,
  not controller transport or host-render latency.
- Network and soak (TMB-022, AWDL off): both phones under 0.2% loss + late,
  sample-age p95 about 20 ms.
- The owner physically exercised the iPhone on the same setup, observed the
  same response as Android and accepts that parity check as final iPhone
  feasibility evidence.

Accepted evidence exception:
- There is no separate retained iPhone percentile set, and only 27 Galaxy
  display transitions are camera-correlated. The project owner explicitly
  accepts the stage-attributed bound and same-setup iPhone parity check instead
  of requiring another recording.

Consequences:
- Gate A is closed and M2 is unblocked, beginning with TMB-026.
- Custom hardware and phone-side early detection are not needed.
- TMB-058 will re-run latency and packet tests on the release candidate;
  regressions create new remediation work rather than rewriting this record.
