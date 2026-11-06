# TMB-033 — Build detector evaluation and tuning reports

**Status:** Blocked — detector dependency incomplete  
**Labels:** `detection`, `observability`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-032

### Implementation steps

1. Calculate precision, recall, false negatives, false positives and trigger lead/lag.
2. Break metrics down by device, player, handedness, shot label and speed.
3. Tune only on the designated tuning sessions.
4. Evaluate once on held-out sessions and report results separately.
5. Save detector configuration with the report.

### Acceptance criteria

- Overall real-swing detection is at least 95% on held-out data.
- Live idle/normal handling produces fewer than one false swing per 10 minutes.
- No device/player subgroup failure is hidden by the aggregate metric.

### Evidence

- Versioned detector evaluation report
- Detector configuration used for evaluation


