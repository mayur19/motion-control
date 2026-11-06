# TMB-062 — Decide the next display-host target

**Status:** Blocked — Release 1 archive dependency incomplete  
**Labels:** `gate`, `architecture`, `product`  
**Estimate:** 1 day  
**Dependencies:** TMB-061

### Implementation steps

1. Collect evidence about where intended users will display and play the game.
2. Compare browser host, Android TV and continued desktop delivery on setup friction, achievable latency, frame rate, networking changes, development cost and distribution.
3. For browser, account for replacing raw UDP with WebRTC DataChannel and required signaling.
4. For Android TV, account for device performance, 60/120 Hz support, game/low-latency mode and Ethernet availability.
5. Select one target or decide to remain desktop-only for the next cycle.
6. Write an ADR and create a separate implementation backlog for the selected target.

### Acceptance criteria

- The decision uses Release 1 measurements and user environment evidence.
- Platform expansion does not weaken the accepted desktop protocol/game boundaries.
- No browser or TV implementation begins without the new ADR and backlog.

### Evidence

- Gate C comparison and ADR


