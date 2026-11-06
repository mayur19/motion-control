# TMB-058 — Re-run latency and packet tests on the release candidate

**Status:** Blocked — release portability dependencies incomplete  
**Labels:** `release`, `quality`, `observability`  
**Estimate:** 1 day  
**Dependencies:** TMB-055, TMB-057

### Implementation steps

1. Run the M1 soak test on the release build.
2. Repeat the 240 FPS latency test on the reference Windows/144 Hz setup.
3. Compare results with Gate A and explain meaningful regressions.
4. Confirm debug/release compiler settings do not alter protocol or timing behavior unexpectedly.

### Acceptance criteria

- Release-candidate metrics meet the PRD targets.
- No statistically/practically meaningful unexplained regression remains.
- Test build identifiers and logs are retained.

### Evidence

- Release-candidate performance report


