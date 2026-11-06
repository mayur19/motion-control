# TMB-029 — Build labeled motion capture and replay tools

**Status:** Done — capture/replay demonstrated on iPhone

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

### Implementation record

- Capture (`capture/motion_capture.gd`, F6 panel `ui/capture_panel.gd`):
  accepted MOTION/CALIBRATION datagrams byte-exact in immutable `raw.jsonl`
  with `raw.sha256`; calibration already in force is seeded at start; HELLO
  (pairing secret) and other control traffic are never stored.
- Labels (player, phone, hand, intended shot, valid) in append-only
  `labels.jsonl`; `tools/capture-labels.py` lists, verifies and corrects by
  appending revisions.
- `detection/detector_pipeline.gd` is the single detector boundary for live
  and replay; it holds a placeholder angular-speed probe until TMB-032.
- Replay (`replay/replay_capture.gd`, `replay/capture_replayer.gd`) verifies
  the checksum, applies the recorded active-session gate, feeds a fresh
  MotionIngest + DetectorPipeline and exports detector config, per-take
  summaries and events as JSON.
- Format: `docs/capture-format.md`. Evidence:
  `docs/evidence/TMB-029-capture-replay.txt` (physical capture replayed
  offline; live and replay events identical; label correction leaves raw
  unchanged).
- Known limits: the replay summary attributes events to takes by arrival
  time; the probe's event count is not a swing count.

