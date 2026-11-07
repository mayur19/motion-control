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
- iPhone tune selection (2026-11-07): compared the original defaults with
  onset 8.5, 9.0 and 9.5 rad/s, refractory 700/800 ms, and rise 15/20 rad/s².
  The lower rise gate had no effect. Selected onset 9.5, refractory 700 and
  retained rise 20 because it met both aggregate tune targets with the fewest
  false triggers: TP 86 / FN 4 / FP 3, recall 95.6%, precision 96.6%, and
  0.51 non-swing triggers per 10 minutes over 19.78 minutes. The original
  defaults produced 502 events and 146.1 non-swing triggers per 10 minutes.
- Subgroups remain explicit: gentle was 28/28; fast was 27/28 with one
  over-trigger; lift recall was 90.5%; and normal was 31/34, but S1 normal
  counts were operator estimates. Data currently covers only iPhone,
  right-hand and player 1, so this is a provisional device-specific tune
  result rather than acceptance evidence.
- Saved exact input configuration and resolved reports:
  `docs/evidence/TMB-033-iphone-tuned-config-v1.json`,
  `docs/evidence/TMB-033-iphone-tune-v1.json` and `.md`. Updated live/replay
  defaults to the selected onset/refractory values; both still use the same
  `DetectorPipeline` configuration.
- Remaining: Galaxy and left-hand/player tune coverage, the one-time S4/N4
  held-out report, and the live idle/handling acceptance check. Do not retune
  on held-out results.
- External-data applicability spike, Stage 1 (2026-11-07): an owner decision
  allows public badminton datasets as supplementary **external/off-domain**
  evidence. They are not part of the TMB-030 tune/held-out split and are not a
  new ticket. `docs/external-dataset-evaluation.md` reviews BadminSense
  BADS_CLL (repository README at `0408092`, CHI 2026 paper arXiv 2603.21825):
  a wrist-worn Galaxy Watch 6 FE with 848 valid overhead strokes from 12
  right-handed players, real shuttle impacts, and CC BY-NC-ND 4.0. It also
  covers the domain gaps compared with a phone held as the racket handle,
  separation of `internal tune` / `internal heldout` / `external/off-domain`,
  why valid-strokes-only data cannot measure false triggers per 10 minutes,
  and the eight metadata items that must be confirmed from a real sample
  before an adapter. Five other datasets are recorded as later candidates
  only. Source manifest: `docs/external-dataset-sources.json` (metadata only).
- Recommendation: **defer**. Units, timestamps, frame, calibration and segment
  boundaries are undocumented; forearm motion thresholds do not transfer to
  racket-frame thresholds; and the NC/ND terms need an owner decision on
  intended use. Stage 2 (one-file sample inspection outside Git, archive
  SHA-256 recorded) waits for owner approval of the license terms and the
  14 GB download. Nothing was downloaded, no external data was committed or
  fed into `DetectorPipeline`, and no internal held-out session was evaluated
  or exposed. No physical or product performance claim can be made from this
  spike.


