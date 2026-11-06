"""Tests for tools/plot-preprocessing.py (TMB-031 before/after plots)."""
import json
import math
import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).with_name("plot-preprocessing.py")


def row(cid: int, i: int) -> dict:
    raw = abs(math.sin(i / 15)) * 6 + (0.3 if i % 2 else -0.3)
    return {"controller_id": cid, "sequence": i, "sensor_monotonic_ns": i * 10_000_000,
            "normalized_angular_speed": raw, "preprocessed_angular_speed": abs(math.sin(i / 15)) * 6,
            "normalized_acceleration": [raw, 0.0, 0.0], "preprocessed_acceleration": [raw * 0.9, 0.0, 0.0],
            "gap_reset": i == 0}


def run(tmp_path: pathlib.Path, rows: list[dict], *args: str) -> subprocess.CompletedProcess:
    series = tmp_path / "series.jsonl"
    series.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    return subprocess.run([sys.executable, "-I", str(SCRIPT), str(series), *args], capture_output=True, text=True)


def test_plots_before_after_and_reports_noise(tmp_path: pathlib.Path) -> None:
    out = tmp_path / "plot.png"
    result = run(tmp_path, [row(7, i) for i in range(300)], "--output", str(out))
    assert result.returncode == 0, result.stderr
    assert out.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
    assert "TMB-031_PLOT_OK controllers=1 samples=300" in result.stdout
    assert "rms_change_rad_s=" in result.stdout and "gap_resets=1" in result.stdout


def test_empty_series_fails_clearly(tmp_path: pathlib.Path) -> None:
    result = run(tmp_path, [], "--output", str(tmp_path / "x.png"))
    assert result.returncode == 2 and "no samples" in result.stderr.lower()
