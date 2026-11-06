# TMB-033 — Build detector evaluation and tuning reports

**Status:** In Progress — tooling under dependency exception; dataset evaluation pending
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

### Implementation record

- Owner decision (2026-11-06): start the evaluation/tuning tooling while
  TMB-030 is incomplete and TMB-032 remains in Review. Synthetic fixtures may
  verify the reporting workflow now; detector tuning, held-out evaluation and
  the acceptance thresholds remain pending real TMB-030 sessions.
- Implemented `tools/detector-evaluation.py` and
  `docs/detector-evaluation.md`. The tool runs the existing Godot replay (or
  consumes saved replay JSON/series), verifies raw checksums and effective
  label revisions, evaluates tune or held-out separately, embeds the exact
  `DetectorPipeline.describe()` value, and reports per-take and aggregate
  count-based TP/FN/FP, recall, precision, non-swing false triggers per 10
  minutes, trigger-to-following-peak estimates and phone/player/hand/shot/speed
  subgroups. Invalid takes and exclude-split sessions are listed, not counted.
- Held-out execution requires `--confirm-heldout`; the documented workflow is
  to freeze the tune-selected configuration, evaluate held-out once and
  archive the versioned JSON/Markdown reports without retuning on them.
- Metric and guardrail verification uses synthetic fixtures. A read-only CLI
  integration smoke against the incomplete iPhone S1/N1 tune split with the
  current default pipeline replayed both captures successfully: 169 triggers
  versus 34 estimated swing counts, giving count-based TP 34 / FN 0 / FP 135
  and precision 0.201. Non-swing takes had 84 triggers over 5.400 minutes
  (155.56 per 10 minutes): idle 0, handling 58, walking 26. This is a
  tune-only diagnostic, not held-out or acceptance evidence; count matching
  cannot establish true recall when the detector over-triggers.
- Real tuning across the completed TMB-030 tune split, the one-time held-out
  report, the live idle/handling acceptance check and any detector threshold
  changes remain pending dataset completion.


