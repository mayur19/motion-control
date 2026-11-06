# TMB-025 — Gate A decision: continue, remediate or stop

**Status:** Blocked — awaiting TMB-022/TMB-024 physical evidence  
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


