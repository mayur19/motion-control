"""Synthetic-log tests for tools/plot-normalization.py (TMB-028 evidence plots)."""
import json
import math
import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).with_name("plot-normalization.py")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def normalized(cid: int, seq: int) -> dict:
    w = math.sin(seq / 10)
    return {
        "record_type": "normalized_sample", "controller_id": cid, "sequence": seq,
        "sensor_monotonic_ns": 1_000_000_000 + seq * 10_000_000,
        "raw_acceleration": [w, 0.0, -w], "raw_angular_velocity": [-w, 2 * w, 0.1],
        "raw_orientation": [0.0, 0.0, 0.0, 1.0],
        "normalized_acceleration": [w, 0.0, w], "normalized_angular_velocity": [w, 2 * w, -0.1],
        "normalized_orientation": [0.0, 0.0, 0.0, 1.0],
    }


def run(tmp_path: pathlib.Path, records: list[dict], *args: str) -> subprocess.CompletedProcess:
    log = tmp_path / "s.jsonl"
    log.write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
    return subprocess.run([sys.executable, "-I", str(SCRIPT), str(log), *args],
                          capture_output=True, text=True)


def test_plots_raw_beside_normalized_for_each_controller(tmp_path: pathlib.Path) -> None:
    records = [{"record_type": "packet", "message_type": 5}]
    records += [normalized(7, i) for i in range(50)] + [normalized(8, i) for i in range(30)]
    out = tmp_path / "plot.png"
    result = run(tmp_path, records, "--output", str(out))
    assert result.returncode == 0, result.stderr
    assert out.read_bytes()[:8] == PNG_MAGIC
    assert "TMB-028_PLOT_OK controllers=2 samples=80" in result.stdout


def test_controller_filter(tmp_path: pathlib.Path) -> None:
    records = [normalized(7, i) for i in range(50)] + [normalized(8, i) for i in range(30)]
    out = tmp_path / "plot.png"
    result = run(tmp_path, records, "--output", str(out), "--controller", "8")
    assert result.returncode == 0, result.stderr
    assert "controllers=1 samples=30" in result.stdout


def test_log_without_normalized_records_fails_clearly(tmp_path: pathlib.Path) -> None:
    result = run(tmp_path, [{"record_type": "packet"}], "--output", str(tmp_path / "x.png"))
    assert result.returncode == 2
    assert "--log-normalized-motion" in result.stderr
    assert not (tmp_path / "x.png").exists()


def test_truncated_last_line_is_ignored(tmp_path: pathlib.Path) -> None:
    log = tmp_path / "s.jsonl"
    text = "\n".join(json.dumps(normalized(7, i)) for i in range(10)) + '\n{"record_type": "norm'
    log.write_text(text, encoding="utf-8")
    out = tmp_path / "plot.png"
    result = subprocess.run([sys.executable, "-I", str(SCRIPT), str(log), "--output", str(out)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "samples=10" in result.stdout
