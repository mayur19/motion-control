# TMB-046 — Implement smash and clear outcomes

**Status:** Blocked — two-player/shot-intent dependencies incomplete  
**Labels:** `gameplay`, `detection`  
**Estimate:** 1 day  
**Dependencies:** TMB-034, TMB-045

### Implementation steps

1. Define gameplay-space smash and clear intent boundaries.
2. Map power, angle, swing plane and timing to distinct trajectories.
3. Tune with representative replays from both phones.
4. Add visual feedback that distinguishes the outcomes.

### Acceptance criteria

- Testers can intentionally produce both outcomes above chance.
- Equivalent normalized intents behave the same regardless of phone.
- Harder physical swings are not required for a successful smash.

### Evidence

- Replay/outcome matrix
- Cross-device comparison


