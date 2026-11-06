"""Synthetic-video tests for tools/latency-frames.py (TMB-024 review aid)."""
import pathlib
import subprocess
import sys

import pytest

SCRIPT = pathlib.Path(__file__).with_name("latency-frames.py")
WIDTH, HEIGHT = 160, 96
MARKER = (10, 30, 30, 30)    # x, y, w, h
DISPLAY = (110, 30, 30, 30)
# (frame the marker starts moving, frames until the display changes)
TAKES = [(60, 12), (300, 15), (540, 19)]
FRAMES = 760


def draw_box(frame: bytearray, x: int, y: int, w: int, h: int, value: int) -> None:
    for row in range(y, y + h):
        start = row * WIDTH + x
        frame[start:start + w] = bytes([value]) * w


def frame_at(n: int) -> bytes:
    frame = bytearray(WIDTH * HEIGHT)  # black
    marker_x = 15
    for start, delay in TAKES:
        if start <= n < start + 120:
            marker_x = 15 + min(10, 2 * (n - start + 1))  # moves right from `start`
    draw_box(frame, marker_x, 35, 12, 12, 255)
    lit = any(start + delay <= n < start + delay + 120 for start, delay in TAKES)
    draw_box(frame, *DISPLAY, 255 if lit else 0)
    return bytes(frame)


def make_video(path: pathlib.Path, fps: int, frames: int = FRAMES) -> None:
    encoder = subprocess.Popen(
        ["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "gray",
         "-s", f"{WIDTH}x{HEIGHT}", "-r", str(fps), "-i", "-", "-c:v", "ffv1", str(path)],
        stdin=subprocess.PIPE,
    )
    for n in range(frames):
        encoder.stdin.write(frame_at(n))
    encoder.stdin.close()
    assert encoder.wait() == 0


def run(video: pathlib.Path, *extra: str) -> subprocess.CompletedProcess:
    roi = lambda r: ",".join(map(str, r))
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), str(video), "--marker", roi(MARKER),
         "--display", roi(DISPLAY), *extra],
        capture_output=True, text=True,
    )


@pytest.fixture(scope="module")
def video_240(tmp_path_factory) -> pathlib.Path:
    path = tmp_path_factory.mktemp("v") / "swings.mkv"
    make_video(path, 240)
    return path


def test_recovers_known_frames_and_latencies(video_240):
    result = run(video_240)
    assert result.returncode == 0, result.stderr
    rows = [line.split(",") for line in result.stdout.splitlines() if line[:1].isdigit()]
    assert [(int(r[1]), int(r[2])) for r in rows] == [(s, s + d) for s, d in TAKES]
    latencies = [round(float(r[3]), 3) for r in rows]
    assert latencies == [round(d * 1000 / 240, 3) for _, d in TAKES]  # 50.0, 62.5, 79.167


def test_reports_measured_fps_and_low_sample_percentiles(video_240):
    out = run(video_240).stdout
    assert "fps=240.000" in out
    assert "takes=3" in out and "median=62.500" in out
    assert "low-sample" in out


def test_warns_when_video_is_not_240_fps(tmp_path):
    path = tmp_path / "slow.mkv"
    make_video(path, 60, frames=200)
    result = run(path)
    assert "WARNING" in result.stderr and "240" in result.stderr


def test_writes_review_contact_sheets(video_240, tmp_path):
    sheets = tmp_path / "sheets"
    result = run(video_240, "--contact-dir", str(sheets))
    assert result.returncode == 0, result.stderr
    names = sorted(p.name for p in sheets.glob("*.png"))
    assert names == [f"take-{i:02d}-{kind}.png" for i in (1, 2, 3) for kind in ("display", "start")]


def test_rejects_roi_outside_frame(video_240):
    result = subprocess.run(
        [sys.executable, "-I", str(SCRIPT), str(video_240), "--marker", "150,90,30,30",
         "--display", ",".join(map(str, DISPLAY))],
        capture_output=True, text=True,
    )
    assert result.returncode != 0 and "outside" in result.stderr
