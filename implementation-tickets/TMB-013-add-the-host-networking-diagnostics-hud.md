# TMB-013 — Add the host networking diagnostics HUD

**Status:** Done  
**Labels:** `observability`, `host`  
**Estimate:** 1 day  
**Dependencies:** TMB-011, TMB-012

### Implementation steps

1. Add separate panels for Player 1 and Player 2.
2. Show endpoint, status, packet Hz, loss, duplicate, reorder, jitter and last-packet age.
3. Plot recent accelerometer and gyroscope values.
4. Add a clear visual warning for stale or disconnected input.
5. Add keyboard/debug controls to show/hide diagnostics without changing collection behavior.

### Acceptance criteria

- Metrics update without allocating unbounded graph history.
- Synthetic impairment changes are visible and agree with run summaries.
- The HUD remains legible at 1080p.

### Evidence

- [Clean 1080p HUD screenshot](../docs/evidence/TMB-013-hud-clean.png)
- [Impaired 1080p HUD screenshot](../docs/evidence/TMB-013-hud-impaired.png)
- [Automated and live-run evidence](../docs/evidence/TMB-013-diagnostics-hud.txt)


