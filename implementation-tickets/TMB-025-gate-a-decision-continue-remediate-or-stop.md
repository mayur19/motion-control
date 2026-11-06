# TMB-025 — Gate A decision: continue, remediate or stop

**Status:** Provisional `GO` (owner decision, 2026-11-06); final decision pending camera-measured latency for both phones  
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

**2026-11-06: provisional `GO` (project owner).** This is not a final `GO`.

Basis:
- Galaxy M14 5G logged software latency over 103 stimulus triggers, from the
  phone sensor timestamp to the host render marker: median 19.6 ms, p95
  38.9 ms, max 40.5 ms (`docs/evidence/TMB-024-galaxy-latency.txt`).
- Uncovered stages are estimated, not measured: display scan-out and panel
  response (up to about 8.3 ms at 120 Hz, plus a few ms) and gyro filtering
  (a few ms). Estimated end-to-end: median about 30 ms, worst about 55 ms,
  against the PRD target of median < 50 ms and p99 < 80 ms.
- The 240 FPS video is consistent with low latency (the flash appears within
  2-5 frames of the first visible motion), but its frame rule produced only a
  lower bound, so it is not a measurement.
- Network and soak (TMB-022, AWDL off): both phones under 0.2% loss + late,
  sample-age p95 about 20 ms.

Known gaps (the decision is provisional because of these):
- No valid camera-measured latency for either phone. The iPhone 17e has no
  end-to-end figure at all (it needs a second 240 FPS camera).
- Attribution beyond software stages (display, sensor filter) is assumed.

Conditions:
- **Owed before a final `GO`:** a valid TMB-024 camera run for both phones
  using the in-plane-rotation method in `docs/test-plans/end-to-end-latency.md`.
- **Revocation:** if either phone's camera-measured median is 50 ms or more,
  or its p99 is 80 ms or more, this becomes `REMEDIATE AND RETEST` and M2 work
  pauses until remediation tickets exist.
- Custom hardware and phone-side early detection: not needed on current
  evidence; not investigated.
