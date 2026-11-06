# TMB-029 — Build labeled motion capture and replay tools

**Status:** Ready

**Labels:** `detection`, `observability`, `quality`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-012, TMB-028

### Implementation steps

1. Add capture controls for player, phone, handedness, intended shot and valid/invalid take.
2. Store labels separately from immutable raw motion records.
3. Build an offline replay path that feeds recorded samples through the same normalization/detector interfaces as live data.
4. Add repeatable detector configuration to each replay result.
5. Export machine-readable event and metric summaries.

### Acceptance criteria

- A recorded session can be replayed without either phone connected.
- Live and replay pipelines use the same detector implementation.
- Labels can be corrected without rewriting raw sensor values.

### Evidence

- One capture/replay demonstration
- Documented capture format


