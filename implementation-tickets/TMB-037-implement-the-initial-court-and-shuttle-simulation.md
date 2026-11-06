# TMB-037 — Implement the initial court and shuttle simulation

**Status:** Blocked — gameplay dependency chain incomplete  
**Labels:** `gameplay`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-036

### Implementation steps

1. Create a simple readable court, net and shuttle representation.
2. Define shuttle state using deterministic position/velocity/trajectory parameters.
3. Implement serve, net crossing, ground contact and out-of-bounds resolution.
4. Expose gravity, drag/trajectory and speed as debug-tunable values.
5. Prioritize predictable game feel over full aerodynamic simulation.

### Acceptance criteria

- A scripted rally crosses the net and resolves in or out deterministically.
- Simulation behavior does not change with render refresh.
- Tuning values can be changed without code edits.

### Evidence

- Scripted rally recording
- Determinism test output


