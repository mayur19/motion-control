#!/usr/bin/env python3
"""Propose swing-start and display-change frames in a 240 FPS latency video.

Usage:
  python3 -I tools/latency-frames.py VIDEO --marker X,Y,W,H --display X,Y,W,H
      [--contact-dir DIR] [--marker-threshold N] [--display-threshold N]

A **review aid** for docs/test-plans/end-to-end-latency.md (TMB-024). It applies
the plan's frame rule to two regions of interest (ROIs, in source pixels):
  F_display: first frame whose display-ROI brightness leaves its rest level.
  F_start:   first frame of the unbroken marker-motion run that is still
             under way at F_display (searched up to 500 ms back).
Candidates must still be confirmed by two blinded reviewers as the plan
requires; --contact-dir writes the frames around each candidate for that.
Prints CSV rows plus median / nearest-rank p95 / p99 and the measured FPS.
Requires ffmpeg and ffprobe on PATH.
"""
import argparse
import json
import math
import pathlib
import statistics
import subprocess
import sys

EXPECTED_FPS = 240.0
FPS_TOLERANCE = 5.0
ANALYSIS_SIZE = 32          # ROIs are downscaled to at most 32x32 for analysis
REST_FRAMES = 24            # 100 ms at 240 FPS establishes the display rest level
LOOKBACK_FRAMES = 120       # 500 ms search window before each display change
CONTACT_BEFORE, CONTACT_AFTER = 4, 3
MOTION_GAP_FRAMES = 2      # still frames tolerated inside one swing


def parse_roi(text: str) -> tuple:
    try:
        x, y, w, h = (int(v) for v in text.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError(f"ROI must be X,Y,W,H integers: {text!r}")
    if w <= 0 or h <= 0 or x < 0 or y < 0:
        raise argparse.ArgumentTypeError(f"ROI must be non-negative with positive size: {text!r}")
    return x, y, w, h


def probe(video: pathlib.Path) -> dict:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height,avg_frame_rate,r_frame_rate", "-of", "json", str(video)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"ffprobe failed: {result.stderr.strip()}")
    stream = json.loads(result.stdout)["streams"][0]
    rate = stream.get("avg_frame_rate") or stream.get("r_frame_rate")
    numerator, denominator = (int(v) for v in rate.split("/"))
    if denominator == 0:
        numerator, denominator = (int(v) for v in stream["r_frame_rate"].split("/"))
    return {"width": stream["width"], "height": stream["height"], "fps": numerator / denominator}


def check_roi(name: str, roi: tuple, info: dict) -> None:
    x, y, w, h = roi
    if x + w > info["width"] or y + h > info["height"]:
        raise SystemExit(f"{name} ROI {roi} is outside the {info['width']}x{info['height']} frame")


def roi_frames(video: pathlib.Path, roi: tuple) -> tuple:
    """Decodes one ROI as grayscale frames; returns (frames, pixels_per_frame)."""
    x, y, w, h = roi
    sw, sh = min(w, ANALYSIS_SIZE), min(h, ANALYSIS_SIZE)
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(video), "-vf",
         f"crop={w}:{h}:{x}:{y},scale={sw}:{sh}:flags=area,format=gray",
         "-f", "rawvideo", "-pix_fmt", "gray", "-"],
        capture_output=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"ffmpeg decode failed: {result.stderr.decode(errors='replace').strip()}")
    size = sw * sh
    data = result.stdout
    return [data[i:i + size] for i in range(0, len(data) - size + 1, size)], size


def mean(frame: bytes) -> float:
    return sum(frame) / len(frame)


def difference(a: bytes, b: bytes) -> float:
    return sum(abs(p - q) for p, q in zip(a, b)) / len(a)


def display_onsets(levels: list, threshold: float) -> list:
    """Frames where the display leaves its rest level (onsets only, not returns)."""
    if len(levels) <= REST_FRAMES:
        return []
    # The display is at rest most of the time, so the whole-video median is the
    # rest level (the first frames may already show a stimulus).
    rest = statistics.median(levels)
    active = lambda n: abs(levels[n] - rest) > threshold
    return [n for n in range(REST_FRAMES, len(levels)) if active(n) and not active(n - 1)]


def motion_start(markers: list, display: int, floor: int, threshold: float) -> tuple:
    """Returns (F_start or None, flag) for the swing that caused a display change.

    Walks back from F_display while the marker keeps moving frame to frame
    (tolerating MOTION_GAP_FRAMES still frames, e.g. at a direction change);
    the first frame of that unbroken motion run is the swing onset."""
    limit = max(floor + 1, display - LOOKBACK_FRAMES)
    moving = lambda n: difference(markers[n], markers[n - 1]) > threshold
    latest = next((n for n in range(display, max(limit, display - MOTION_GAP_FRAMES - 1), -1) if moving(n)), None)
    if latest is None:
        return None, "no-motion-at-display"
    start, still = latest, 0
    n = latest - 1
    while n >= limit:
        if moving(n):
            start, still = n, 0
        else:
            still += 1
            if still > MOTION_GAP_FRAMES:
                return start, ""
        n -= 1
    return start, "moving-at-window-start"


def nearest_rank(values: list, quantile: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(quantile * len(ordered)) - 1)]


def write_contact_sheet(video: pathlib.Path, centre: int, path: pathlib.Path) -> None:
    first, last = max(0, centre - CONTACT_BEFORE), centre + CONTACT_AFTER
    count = last - first + 1
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(video), "-vf",
         f"select='between(n,{first},{last})',scale=320:-2,tile={count}x1",
         "-frames:v", "1", "-fps_mode", "vfr", str(path)],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("video", type=pathlib.Path)
    parser.add_argument("--marker", type=parse_roi, required=True, help="phone marker ROI X,Y,W,H")
    parser.add_argument("--display", type=parse_roi, required=True, help="stimulus ROI X,Y,W,H")
    parser.add_argument("--marker-threshold", type=float, default=6.0, help="mean gray-level change")
    parser.add_argument("--display-threshold", type=float, default=25.0, help="mean gray-level change")
    parser.add_argument("--contact-dir", type=pathlib.Path, help="write review frame strips here")
    parser.add_argument(
        "--capture-fps", type=float,
        help="true capture rate when the container is re-timed (iPhone Slo-mo originals store "
             "240 FPS frames in a 30 FPS, 8x-slow container); verify against host log timing",
    )
    args = parser.parse_args()
    if not args.video.is_file():
        raise SystemExit(f"video not found: {args.video}")

    info = probe(args.video)
    container_fps = info["fps"]
    if args.capture_fps is not None:
        if args.capture_fps <= 0:
            raise SystemExit("--capture-fps must be positive")
        info["fps"] = args.capture_fps
    check_roi("marker", args.marker, info)
    check_roi("display", args.display, info)
    if abs(info["fps"] - EXPECTED_FPS) > FPS_TOLERANCE:
        print(f"WARNING: measured {info['fps']:.3f} fps; the plan requires {EXPECTED_FPS:.0f} FPS video. "
              "Latencies below use the measured rate.", file=sys.stderr)

    displays, _ = roi_frames(args.video, args.display)
    markers, _ = roi_frames(args.video, args.marker)
    frames = min(len(displays), len(markers))
    onsets = display_onsets([mean(f) for f in displays[:frames]], args.display_threshold)

    print(f"# video={args.video.name} fps={info['fps']:.3f} container_fps={container_fps:.3f} frames={frames} "
          f"marker={args.marker} display={args.display}")
    print("take,F_start,F_display,latency_ms,flag")
    if args.contact_dir:
        args.contact_dir.mkdir(parents=True, exist_ok=True)
    latencies, floor = [], 0
    for take, display in enumerate(onsets, 1):
        start, flag = motion_start(markers, display, floor, args.marker_threshold)
        floor = display
        if start is None:
            print(f"{take},,{display},,{flag}")
            continue
        latency = (display - start) * 1000.0 / info["fps"]
        if not flag:
            latencies.append(latency)
        print(f"{take},{start},{display},{latency:.3f},{flag}")
        if args.contact_dir:
            write_contact_sheet(args.video, start, args.contact_dir / f"take-{take:02d}-start.png")
            write_contact_sheet(args.video, display, args.contact_dir / f"take-{take:02d}-display.png")

    if latencies:
        note = " (low-sample: p99 is effectively the maximum)" if len(latencies) < 100 else ""
        print(f"# takes={len(latencies)} median={statistics.median(latencies):.3f} "
              f"p95={nearest_rank(latencies, 0.95):.3f} p99={nearest_rank(latencies, 0.99):.3f} "
              f"min={min(latencies):.3f} max={max(latencies):.3f}{note}")
    else:
        print("# takes=0 (no unflagged swings detected)")
    print("# Candidates only: confirm every frame with two blinded reviewers per the test plan.")


if __name__ == "__main__":
    main()
