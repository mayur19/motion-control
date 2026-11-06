# TMB-024 — Document and execute the 240 FPS latency test

**Status:** Deferred — physical phones and 240 FPS camera required  
**Labels:** `quality`, `observability`  
**Estimate:** 1 day  
**Dependencies:** TMB-023

### Implementation steps

1. Document camera placement so the phone motion and screen response appear in the same frame.
2. Fix host connection, Wi-Fi band, screen refresh, power mode and lighting conditions.
3. Define the visual frame-counting rule for swing start and screen response.
4. Record at least 30 controlled swings per phone.
5. Calculate median, p95 and p99 latency.
6. Correlate video results with software-stage timestamps and document measurement uncertainty.

### Acceptance criteria

- The test can be repeated by another person from the document alone.
- Both phones have enough samples to calculate the required percentiles.
- Video-derived and logged results are retained with device/setup metadata.

### Evidence

- `docs/test-plans/end-to-end-latency.md`
- Raw measurements and summary table

### Implementation log

- 2026-11-06: Completed the repeatable camera/setup/frame-counting procedure,
  measurement worksheet, percentile rules, software-log correlation and
  uncertainty calculation in the linked test plan.
- Recording 30 swings per physical phone and calculating measured percentiles
  is deferred by explicit project-owner direction. No synthetic values are used.


- 2026-11-06: Camera availability: the owner's iPhone 17e records Slo-mo 1080p
  at 240 fps, so it can film the Galaxy controller run; the iPhone controller
  run still needs a second 240 FPS camera. Added `tools/latency-frames.py`, a
  frame-assist tool that proposes F_start/F_display candidates per swing,
  measures the video's real FPS and writes review strips (5 synthetic-video
  tests recover known 50.0/62.5/79.167 ms latencies exactly). It does not
  replace the two blinded reviewers. Still deferred: physical execution.
- 2026-11-06: First physical Galaxy run (iPhone Slo-mo 240 fps). Found and
  fixed a host defect: the latency stimulus typed gyro input as Vector3 while
  the decoder delivers an Array, so it never fired on real controller data
  (`b42c44f`). The camera run produced **no valid latency**: the gyro detected
  rotation the camera could not see at this angle, so the flash preceded or
  nearly coincided with visible motion. The plan's visual rule gives only a
  lower bound. Logged software latency (103 triggers): median 19.6 ms, p95
  38.9 ms, max 40.5 ms; estimated end-to-end about 30 ms median and about 55 ms
  worst. The tool gained `--capture-fps` (iPhone 8x-slow containers) and a
  robust rest level and motion-run onset. The plan now specifies in-plane
  rotation. See `docs/evidence/TMB-024-galaxy-latency.txt`.
