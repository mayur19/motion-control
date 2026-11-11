# 240 FPS end-to-end input latency test

**Status:** Gate A accepted via stage-attributed alternative; direct method retained for future tests

**Tickets:** TMB-023, TMB-024

## Fixed setup

Run one phone at a time. Record source revision, host/phone model and OS, app
build, AP model/band/channel, host Ethernet/Wi-Fi interface, display model,
resolution/refresh, game/low-latency mode, VSync setting, host power mode,
camera model and confirmed 240 FPS mode. Lock exposure/focus and use bright,
flicker-free lighting. Do not change setup between phones.

Place the phone and display in the same camera plane. Frame the controller hand
and at least half of the host's latency stimulus region. Use a small rigid visual
marker on the phone/hand so the first motion frame is unambiguous. Mount the
camera perpendicular to the movement plane; neither subject may leave frame.

Start the host in raw latency mode:

```sh
godot --path apps/host-godot -- --latency-test --session-log-max-mb=128
```

The pairing QR stays visible until a phone pairs; the full-screen stimulus
arms itself on the first motion sample from a paired phone. F4 exits or re-arms
it (press F4 to bring the QR back for another phone). `[`/`-` lowers and `]`/`=` raises the
gyro threshold by 0.25 rad/s without rebuilding. Choose the lowest threshold
that does not trigger during ten seconds of stillness and produces exactly one
response for five controlled practice swings. Record the final value. The
700 ms per-controller cooldown prevents a single swing from retriggering.

## Capture protocol

1. Pair the phone and wait for Connected/clock synchronized state.
2. Start the JSONL log and camera before arming the stimulus.
3. Capture at least 30 valid controlled swings. Pause two seconds between swings.
4. A valid take has the phone marker and display continuously visible, one clear
   motion onset, exactly one display transition and a matching
   `raw_latency_stimulus` log event. Retain invalid takes but mark their exclusion
   reason; do not replace inconvenient valid measurements.
5. Repeat the complete sequence for the other phone without changing the setup.

## Camera: iPhone Slo-mo

The project's iPhone 17e records genuine **Slo-mo 1080p HD at 240 fps**
(Settings > Camera > Record Slo-mo). It can film the Android controller run;
the iPhone controller run needs a second 240 FPS camera. Lock focus/exposure
(press and hold on the subject) before recording. Transfer the **original**
file: in Photos choose Share > Options > "All Photos Data", or AirDrop with
that option, so the 240 FPS frames are not re-timed to 30 FPS playback. Check
with `ffprobe` that the stream reports about 240 fps before analysis.

## Lesson from the first Galaxy run (2026-11-06)

With the phone twisting toward or away from the lens, the gyro detected
rotation the camera could not see: the stimulus flashed before, or 2 frames
after, the first visible motion, so the visual frame rule gave only a lower
bound (see `docs/evidence/TMB-024-galaxy-latency.txt`). For a valid run:

- Hold the phone **facing the camera** and rotate it **in the image plane**
  (like a steering wheel), so a high-contrast corner moves sideways from the
  first degree of rotation.
- Keep the marker region on that corner, **away from surfaces the flash
  lights** (the stimulus illuminates the hand and phone).
- Prefer a full-screen stimulus so the display region is unambiguous.

## Frame-assist tool

`tools/latency-frames.py` applies the frame rule below to two rectangles you
choose in the video (phone marker and host stimulus patch). It proposes
`F_start`/`F_display` for every swing, computes the statistics and can write
review strips of the frames around each candidate:

```sh
python3 -I tools/latency-frames.py swing.MOV \
  --marker X,Y,W,H --display X,Y,W,H --contact-dir review/
```

Its output is a candidate list, **not** the measurement: both reviewers still
mark frames independently (blinded to its output and to log timing) and
resolve disagreements; the tool's candidates become a third, recorded opinion.
Flagged takes (`moving-at-window-start`, `no-motion-at-display`) are excluded from
its statistics and need manual review.

## Frame rule and calculation

`F_start` is the first video frame in which the rigid phone marker has visibly
departed from its pre-swing position. `F_display` is the first frame whose
high-contrast region has begun changing; for a scan-out boundary, use the first
frame containing any changed display rows. Two reviewers should independently
mark frames while blinded to log timing and resolve disagreements explicitly.

For 240 FPS video, each frame interval is 4.1667 ms:

```text
video_latency_ms = (F_display - F_start) × 1000 / measured_camera_fps
```

Report the median, nearest-rank p95 and nearest-rank p99 separately for each
phone. With 30 takes, p95 is ordered sample 29 and p99 is sample 30; the p99 is
therefore effectively the maximum and must be labelled as a low-sample estimate.
Also report min/max and the number of included/excluded takes.

## Log correlation and uncertainty

Match each video take to the log by order and visible transition phase. Retain:
sensor time, adjusted sample time, arrival, threshold, simulation marker,
next-frame render marker and software sample-to-render time. Compare logged
sample-to-render latency with video motion-to-display latency; they measure
different start/end boundaries and are not expected to be identical.

Quantization uncertainty is at least ± one camera frame (±4.17 ms at exact
240 FPS), plus motion-onset judgement and display scan-out ambiguity. Report the
measured camera frame rate and use it instead of assuming 240. If exposure spans
a display transition, flag that take and include the chosen boundary rule.

## Measurement worksheet

| Phone | Take | F_start | F_display | Frames | Video ms | Log event/sequence | Software ms | Included? / reason |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- |
| _pending_ | 1 | | | | | | | |

| Phone | N | Median ms | P95 ms | P99 ms | Min/max ms | Uncertainty |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| iPhone | _pending_ | | | | | |
| Pixel | _pending_ | | | | | |

Direct-method raw video/log paths and SHA-256 checksums: _pending_.
Direct motion-onset result: **INCOMPLETE — Gate A uses the accepted alternative below.**

## Gate A accepted alternative (2026-11-06)

The project owner accepted raw gyro-threshold-to-visible response as the Gate A
feasibility boundary after repeated recordings showed that gradual visible
motion onset measures gesture acceleration as well as system response. The
Galaxy run combined 41 logged threshold-to-render samples with 27 correlated
240 FPS display transitions. A conservative display/camera allowance produced
upper bounds of 47.6 ms median and 71.6 ms p99/max. A same-setup iPhone physical
parity check was accepted by the owner in lieu of a separate retained
percentile set. See `docs/test-plans/gate-a-decision.md` for the final decision,
artifact hashes, evidence exception and consequences.

The procedure above remains the preferred direct test for future detector and
release-candidate validation; its pending worksheet does not override the
owner-approved Gate A evidence exception.
