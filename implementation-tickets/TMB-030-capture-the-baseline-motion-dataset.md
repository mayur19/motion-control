# TMB-030 — Capture the baseline motion dataset

**Status:** Ready

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


