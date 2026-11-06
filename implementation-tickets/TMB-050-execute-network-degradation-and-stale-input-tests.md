# TMB-050 — Execute network degradation and stale-input tests

**Status:** Blocked — active-match reconnect dependencies incomplete  
**Labels:** `quality`, `networking`  
**Estimate:** 1 day  
**Dependencies:** TMB-045, TMB-049

### Implementation steps

1. Inject controlled loss, delay, jitter, duplicates and reordering using the synthetic path or network tooling.
2. Verify stale samples are discarded instead of applied late.
3. Verify health state transitions and recovery.
4. Determine playable limits and document expected player messaging.

### Acceptance criteria

- Old swing packets never create delayed hits.
- Severe degradation pauses play instead of silently producing unfair outcomes.
- Normal recovery does not require restarting the match.

### Evidence

- Degradation matrix and host logs


