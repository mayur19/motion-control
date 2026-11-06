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

