# TMB-052 — Conduct four-shot usability verification

**Status:** Blocked — shot/resilience dependencies incomplete  
**Labels:** `quality`, `detection`, `gameplay`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-047, TMB-051

### Implementation steps

1. Ask each player to intentionally perform each shot type without showing the debug classification.
2. Record intended and resulting shot types.
3. Calculate a simple confusion matrix per phone/player.
4. Identify whether failures belong to detection, mapping, tutorial or feedback.

### Acceptance criteria

- Each shot type is distinguishable above chance for both players.
- No shot requires unsafe or maximum-force motion.
- Findings are assigned to a bounded tuning or redesign action.

### Evidence

- Four-shot usability report and confusion matrices


