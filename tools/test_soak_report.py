"""Synthetic-log tests for tools/soak-report.py verdicts."""
import json
import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).with_name("soak-report.py")
S = 1_000_000_000


def interval(t_s, cid, hz=100.0, frame_max=20.0, frame_p99=None, loss=0, state="Connected"):
    frame = {"count": 60, "median": 16.0, "p95": 18.0, "maximum": frame_max}
    if frame_p99 is not None:
        frame["p99"] = frame_p99
    return {
        "record_type": "event", "event": "soak_metrics", "host_monotonic_ns": int(t_s * S),
        "controller_id": cid, "connection_state": state, "interval_seconds": 1.0,
        "received_motion_hz": hz, "actual_sensor_hz": hz, "loss_packets": loss,
        "duplicate_packets": 0, "reordered_packets": 0, "network_jitter_ms": 5.0,
        "clock_rtt_ms": 10.0, "queue_drops": 0, "host_static_memory_bytes": 40_000_000,
        "host_frame_ms": frame,
    }


def packets(cid, start_s, seconds, hz, age_ms):
    out = [{"record_type": "event", "event": "clock_sync", "host_monotonic_ns": int(start_s * S) - 1,
            "controller_id": cid, "offset_ms": 0.0}]
    for i in range(int(seconds * hz)):
        arrival = int((start_s + i / hz) * S)
        out.append({"record_type": "packet", "message_type": 5, "controller_id": cid,
                    "arrival_monotonic_ns": arrival, "sensor_monotonic_ns": arrival - int(age_ms * 1e6)})
    return out


def run(tmp_path, records, *window):
    log = tmp_path / "s.jsonl"
    log.write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
    return subprocess.run([sys.executable, "-I", str(SCRIPT), str(log), *map(str, window)],
                          capture_output=True, text=True)


def healthy(cid, hz=100.0, **kw):
    return [interval(10 + i, cid, hz=hz, **kw) for i in range(10)] + packets(cid, 10, 10, hz, 10.0)


def test_healthy_two_phones_pass_and_idle_controllers_are_ignored(tmp_path):
    records = healthy(1) + healthy(2, hz=250.0) + [interval(12, 99, state="Disconnected")]
    result = run(tmp_path, records, 9)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "TMB-022_SOAK_PASS" in result.stdout
    assert "not measured" in result.stdout


def test_median_rate_threshold_is_99(tmp_path):
    assert "TMB-022_SOAK_PASS" in run(tmp_path, healthy(1, hz=99.0), 9).stdout
    assert "TMB-022_SOAK_FAIL" in run(tmp_path, healthy(1, hz=98.0), 9).stdout


def test_late_samples_fail_the_one_percent_threshold(tmp_path):
    records = [interval(10 + i, 1) for i in range(10)] + packets(1, 10, 10, 100.0, 80.0)
    out = run(tmp_path, records, 9).stdout
    assert "dropped+late    100.000%" in out and "TMB-022_SOAK_FAIL" in out


def test_frame_over_150_ms_fails(tmp_path):
    records = healthy(1)
    records[3]["host_frame_ms"]["maximum"] = 151.0
    out = run(tmp_path, records, 9).stdout
    assert "[FAIL <= 150 ms]" in out


def test_logged_p99_is_used_when_present(tmp_path):
    out = run(tmp_path, healthy(1, frame_p99=55.0), 9).stdout
    assert "per-second p99" in out and "[FAIL < 50 ms]" in out


def test_host_intervals_are_counted_once_across_controllers(tmp_path):
    out = run(tmp_path, healthy(1) + healthy(2), 9).stdout
    assert "of 600 frames" in out  # 10 host intervals x 60 frames, not 1,200
