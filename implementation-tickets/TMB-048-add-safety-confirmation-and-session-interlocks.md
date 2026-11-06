# TMB-048 — Add safety confirmation and session interlocks

**Status:** Blocked — two-player gameplay dependency incomplete  
**Labels:** `safety`, `controller-ios`, `controller-android`, `host`  
**Estimate:** 1 day  
**Dependencies:** TMB-019, TMB-045

### Implementation steps

1. Require wrist-strap/tether confirmation before calibration.
2. Require clear-space confirmation before match start.
3. Show safety state on phones and host.
4. Invalidate confirmation when starting a new session, not merely a new point.
5. Pause the match immediately on controller disconnect or backgrounding.

### Acceptance criteria

- A new session cannot reach active play without both confirmations.
- Disconnect/backgrounding prevents further swing acceptance.
- Safety prompts emphasize controlled motion and timing over force.

### Evidence

- Safety-flow screenshots
- Interlock test results


