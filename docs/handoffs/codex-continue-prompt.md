# Codex handoff — continue development (2026-11-06, after `7836d3c`)

Paste the block below into Codex.

```text
You are continuing development of Two-Phone Motion Badminton in
~/IdeaProjects/motion-control (branch main, remote origin =
private github.com/mayur19/motion-control). Two phones act as badminton-racket
motion controllers for a Godot 4.7 desktop host over UDP.

Read first, in order:
1. AGENTS.md: rules, commands, current state and gotchas. Follow its hard
   rules exactly.
2. git log --oneline -15 and git status. Never discard or overwrite
   uncommitted work you did not make.
3. implementation-tickets/README.md and the ticket you work on, including its
   implementation log.
4. docs/capture-format.md, docs/motion-preprocessing.md,
   docs/swing-detection.md and docs/test-plans/tmb-030-dataset-capture-plan.md.

Where things stand:
- Done and physically verified: TMB-001–029 (pairing, clock sync, reconnect,
  soak, Gate A GO, racket frame, calibration, host calibration gate, labeled
  capture/replay).
- TMB-030 dataset: In Progress and recorded only by the owner. Done: iPhone S1
  (34 swings, tune) and N1 (tune). Target per phone: 100 swings and 20
  non-swing minutes, with S4/N4 held out. The Galaxy is borrowed and only
  intermittently available.
- TMB-031 preprocessing and TMB-032 early_rise detector: Review under an
  owner-approved dependency exception. Thresholds are provisional; the
  backswing vs forward-swing question is open.

Your task: build TMB-033 evaluation and tuning tooling against the existing
replay pipeline, so it is ready as dataset sessions arrive.
- Input: capture directories, dataset-splits.json (tune / heldout / exclude),
  effective labels (latest revision; swing_count, intended_shot, speed, hand,
  phone, player, valid) and replay results from
  apps/host-godot/replay/replay_capture.gd.
- Compute per take, then aggregate: true positives, false negatives, false
  positives, recall and precision, and false triggers per 10 minutes on
  non-swing takes. Swing takes only have counts (no per-swing timestamps), so
  document the matching rule explicitly: count-based per take, with
  over-triggering counted as false positives. Estimate trigger lead/lag
  against the following angular-speed peak, and state its limits.
- Break down by phone, player, hand, shot and speed. Never let the aggregate
  hide a subgroup.
- Tune only on the tune split. Evaluate held-out sessions once, report them
  separately, and save the exact detector + preprocessing config
  (DetectorPipeline.describe()) with every report.
- Exclude invalid takes and exclude-split sessions from metrics, but list
  them.
- Deliver a tool (Python under tools/ with pytest tests, or GDScript where it
  must run the pipeline) plus a short doc. Use synthetic fixtures for tests.
  Don't commit real captures; they live in the host user-data captures folder.

Working rules:
- Tests first: write the failing test, run it red, implement, run it green.
  Run every suite before committing:
    godot --headless --path apps/host-godot --import
    for each apps/host-godot/tests/*_test.gd: run it under `timeout 90` and
      require TMB-..._OK plus exit 0
    godot --headless --path apps/host-godot -- --smoke-test
    python3 -m pytest -q tools/
- Conventional commits (feat:, fix:, docs:, test:, chore:). Commit in focused
  steps. Don't push unless the owner asks.
- Evidence must be honest: never present synthetic or estimated results as
  physical measurements. Record gaps and owner decisions in the ticket
  implementation log. Never invent swing counts or labels; S1's counts are
  operator estimates and are acceptable only because S1 is a tune session.
- Never print or commit pairing secrets, UDIDs, ECIDs, serials or the Apple
  team ID. Don't use the host's --print-session flag, and don't open host
  screenshots (they show the pairing code).
- Physical-device steps need the owner. Ask before planning anything on the
  Galaxy. Keep human sessions to 6 minutes or less.
- If a ticket's dependency is incomplete, stop and ask the owner for an
  explicit exception before proceeding, then record it in the ticket log.

When you finish a step, report: commits, test results, what's verified versus
pending, and any decision the owner needs to make.
```
