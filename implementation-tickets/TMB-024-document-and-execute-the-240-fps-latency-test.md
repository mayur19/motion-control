# TMB-024 — Document and execute the 240 FPS latency test

**Status:** Accepted — closed with owner-approved stage-attributed evidence

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
- 2026-11-06: Second Galaxy run (`IMG_9712.MOV`) corrected the camera angle and
  captured 27 display transitions matched to a 41-trigger host-log run. The
  owner accepted raw-threshold-to-visible latency as the feasibility boundary:
  software median 30.1 ms and p99/max 54.1 ms; conservative visible bounds
  median 47.6 ms and p99/max 71.6 ms. The owner then performed a same-setup
  iPhone parity check and accepted it as final evidence. Gate A waived the
  separate 30-take-per-phone requirement; see the Gate A decision record.
