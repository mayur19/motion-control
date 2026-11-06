# TMB-045 — Integrate two simultaneous players into gameplay

**Status:** Blocked — one-player validation incomplete  
**Labels:** `gameplay`, `networking`  
**Estimate:** 1 day  
**Dependencies:** TMB-044

### Implementation steps

1. Route Player 1 and Player 2 shot intents to separate gameplay entities.
2. Preserve assignment across points and rematches.
3. Ensure one player's packet delay or burst cannot block the other.
4. Add two-player scripted event tests.

### Acceptance criteria

- Both players can alternate hits in one rally.
- Events cannot be consumed by the wrong player.
- One disconnected/degraded controller does not block host processing of the other.

### Evidence

- Two-player rally capture
- Assignment/isolation test output


