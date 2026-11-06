# TMB-038 — Implement automatic player positioning

**Status:** Blocked — gameplay dependency chain incomplete  
**Labels:** `gameplay`  
**Estimate:** 1 day  
**Dependencies:** TMB-037

### Implementation steps

1. Predict the shuttle landing/intercept area.
2. Move the active player toward the playable intercept position.
3. Preserve a visible timing window so the player still controls the hit.
4. Add movement-speed and anticipation tuning controls.
5. Prevent impossible teleporting or court-boundary violations.

### Acceptance criteria

- The player reaches a playable position for standard trajectories.
- Movement does not itself trigger or guarantee a shot.
- Positioning remains understandable to a first-time tester.

### Evidence

- Automated trajectory/intercept cases
- Short gameplay capture


