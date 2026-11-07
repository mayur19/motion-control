# TMB-030 — Capture the baseline motion dataset

**Status:** In Progress — plan and tooling ready; owner capture sessions pending

**Labels:** `detection`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-029

### Implementation steps

1. Capture at least 100 genuine swings per phone across intended shot motions and speeds.
2. Include both intended players and handedness variants where available.
3. Capture at least 20 minutes of idle, menu use, walking/handling and non-swing movement.
4. Mark unsafe, ambiguous or incorrectly performed takes as excluded without deleting them.
5. Produce a dataset inventory and identify coverage gaps.

### Acceptance criteria

- Both phones meet the minimum positive and negative-data volume.
- Train/tune and held-out evaluation sessions are separated by recording session, not random individual samples.
- Dataset metadata contains no personal account information.

### Evidence

- Dataset inventory and coverage report
- Immutable raw capture checksums

### Implementation record

- Plan: `docs/test-plans/tmb-030-dataset-capture-plan.md` (≤ 6-minute
  sessions; per phone 4 swing + 4 non-swing sessions; the 4th of each is
  held-out, fixed by session order before recording; reduced-volume option and
  its consequences for TMB-033 stated for an owner decision).
- Labels gained optional `speed` and `swing_count` (F6 panel,
  `capture-labels.py`, replay summaries).
- `tools/dataset-inventory.py` verifies checksums, applies
  `dataset-splits.json` (`tune`, `heldout`, `exclude`), and reports per-phone
  swings and non-swing minutes by shot, speed, hand, player and split,
  excluded takes, coverage gaps, a privacy review of unexpected fields and the
  raw SHA-256 list (Markdown/JSON).
- The two TMB-029 demonstration captures are marked `exclude`.
- Known gap before any capture: only one player is available.
- Owner decision (2026-11-06): commit to the full target (per phone 4 swing +
  4 non-swing sessions of <= 6 minutes, spread over days). The reduced-volume
  option was declined.
- 2026-11-06 iPhone S1 (swing, tune) captured: 34 swings (smash 11,
  clear 8, drop 8, lift 7; speed normal, peaks 22-32 rad/s) and 1.3 min of
  handling. Speed and swing counts were set afterwards as label revision 2;
  the swing counts are operator estimates ("over 10", "7-9"), which is
  acceptable for a tune session. Process for later sessions, required for
  the held-out S4/N4: count swings aloud, do exactly the planned number, and
  set Speed and Swings in take before END TAKE.
- Inventory after S1: iPhone 34/100 swings, 1.3/20 non-swing minutes.
- 2026-11-06 iPhone N1 (non-swing, tune) captured: idle 1.85 min, handling
  1.26 min, walking 1.02 min at 100 Hz. Handling and walking peaked at 8.1
  and 8.4 rad/s, well above the provisional 3 rad/s onset, so they are useful
  hard negatives for TMB-033.
- Inventory after N1: iPhone 34/100 swings, 5.4/20 non-swing minutes.
- 2026-11-07 iPhone S2 (swing, tune) captured: 28 right-handed gentle
  swings, exactly 7 each for smash, clear, drop and lift, plus 1.11 minutes
  of handling. The operator counted exactly seven during every swing take but
  left the UI count at zero; the confirmed counts were appended afterwards as
  label revision 2. Unlike S1, these are exact operator counts, not estimates.
  The raw checksum still verifies after the append-only label corrections.
- Default-pipeline replay succeeded for every S2 take and showed the expected
  provisional-detector over-triggering: 16/11/16/11 events for the four
  seven-swing takes and 18 events in handling. This is tune-only diagnostic
  information, not held-out or acceptance evidence.
- Inventory after S2: iPhone 62/100 swings, 6.51/20 non-swing minutes
  (normal 34, gentle 28; all currently right-handed and player 1).
- 2026-11-07 iPhone N2 (non-swing, tune) captured: idle 1.78 minutes,
  handling 1.24 minutes and walking 2.02 minutes (5.04 minutes total). An
  earlier aborted attempt containing only a six-second idle take is retained
  with split `exclude`, per the owner's direction; it is not counted.
- Default-pipeline replay succeeded for N2 and produced 10 idle, 17 handling
  and 64 walking triggers. These are useful hard negatives demonstrating the
  provisional detector's over-triggering, not held-out or acceptance results.
- Inventory after N2: iPhone 62/100 swings, 11.55/20 non-swing minutes
  (idle 3.63, handling 4.89, walking 3.03; all tune split).
- 2026-11-07 iPhone S3 (swing, tune) captured: 28 right-handed fast swings,
  exactly 7 each for smash, clear, drop and lift, plus 1.45 minutes of
  handling. The handling take accidentally retained speed `fast` and count 7;
  the owner confirmed that it contained no swings and should be speed `none`,
  count 0, which was appended as label revision 2. The raw checksum verifies.
- Default-pipeline replay succeeded for S3 and produced 21/17/17/19 events
  for the four seven-swing takes and 25 events in handling, again confirming
  substantial provisional-detector over-triggering. This is tune-only
  diagnostic information, not held-out or acceptance evidence.
- Inventory after S3: iPhone 90/100 swings and 13.00/20 non-swing minutes.
  The three tune swing sessions now cover normal 34, gentle 28 and fast 28;
  all are currently right-handed and player 1. S4 remains held out.

