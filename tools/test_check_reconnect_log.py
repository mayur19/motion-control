"""Synthetic-log tests for tools/check-reconnect-log.py."""
import json
import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).with_name("check-reconnect-log.py")
SECOND_NS = 1_000_000_000
CID = 1234


def event(t_s: float, name: str, **fields) -> dict:
    return {"record_type": "event", "event": name, "host_monotonic_ns": int(t_s * SECOND_NS), **fields}


def scenario(rehello_s: float, new_id: int = CID, rate: float = 99.0) -> list:
    records = [
        event(1, "pairing", reason="paired", player=1, controller_id=CID, endpoint="a:1"),
        event(1, "controller_state", controller_id=CID, state="Reconnecting"),
        event(2, "controller_state", controller_id=CID, state="Connected"),
        event(10, "controller_state", controller_id=CID, state="Paused"),
        event(12, "controller_state", controller_id=CID, state="Disconnected"),
        event(rehello_s, "pairing", reason="reconnect", player=1, controller_id=new_id, endpoint="a:2"),
        event(rehello_s, "controller_state", controller_id=new_id, state="Reconnecting"),
        event(rehello_s + 0.5, "soak_metrics", controller_id=new_id, received_motion_hz=0, connection_state="Reconnecting"),
        event(rehello_s + 0.8, "clock_sync", controller_id=new_id, samples=1, rtt_ms=20.0),
        event(rehello_s + 0.9, "controller_state", controller_id=new_id, state="Connected"),
    ]
    records += [
        event(rehello_s + 2 + i, "soak_metrics", controller_id=new_id, received_motion_hz=rate, connection_state="Connected")
        for i in range(6)
    ]
    return records


def run(tmp_path: pathlib.Path, records: list) -> subprocess.CompletedProcess:
    log = tmp_path / "session.jsonl"
    log.write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
    return subprocess.run([sys.executable, "-I", str(SCRIPT), str(log)], capture_output=True, text=True)


def test_timely_same_reservation_reconnect_passes(tmp_path):
    result = run(tmp_path, scenario(rehello_s=18))
    assert result.returncode == 0, result.stdout
    assert "TMB-021_PHYSICAL_RECONNECT_OK" in result.stdout


def test_late_reconnect_fails_reservation_check(tmp_path):
    result = run(tmp_path, scenario(rehello_s=40))
    assert result.returncode == 1
    assert "FAIL  within 15 s reservation" in result.stdout


def test_new_controller_id_fails_identity_check(tmp_path):
    result = run(tmp_path, scenario(rehello_s=18, new_id=999))
    assert result.returncode == 1
    assert "FAIL  same controller ID and P1" in result.stdout


def test_low_resumed_rate_fails(tmp_path):
    result = run(tmp_path, scenario(rehello_s=18, rate=60.0))
    assert result.returncode == 1
    assert "FAIL  motion resumes" in result.stdout


def test_truncated_final_line_is_reported_not_fatal(tmp_path):
    log = tmp_path / "session.jsonl"
    body = "\n".join(json.dumps(r) for r in scenario(rehello_s=18))
    log.write_text(body + '\n{"record_type":"pack', encoding="utf-8")
    result = subprocess.run([sys.executable, "-I", str(SCRIPT), str(log)], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout
    assert "NOTE  ignored unterminated final line" in result.stdout


def test_corrupt_middle_line_is_fatal(tmp_path):
    records = [json.dumps(r) for r in scenario(rehello_s=18)]
    records.insert(3, "{not json")
    log = tmp_path / "session.jsonl"
    log.write_text("\n".join(records) + "\n", encoding="utf-8")
    result = subprocess.run([sys.executable, "-I", str(SCRIPT), str(log)], capture_output=True, text=True)
    assert result.returncode != 0
    assert "invalid JSON" in result.stderr


def test_connected_logged_just_before_its_own_clock_sync_passes(tmp_path):
    # One PONG emits a single metrics signal; the connection manager (connected
    # first) logs Connected microseconds before the logger writes clock_sync.
    records = scenario(rehello_s=18)
    for r in records:
        if r["event"] == "controller_state" and r["state"] == "Connected" and r["host_monotonic_ns"] > 15 * SECOND_NS:
            r["host_monotonic_ns"] = int(18.8 * SECOND_NS) - 11_000
            r["reason"] = "clock synchronized"
    result = run(tmp_path, records)
    assert result.returncode == 0, result.stdout


def test_connected_long_before_sync_still_fails(tmp_path):
    records = scenario(rehello_s=18)
    for r in records:
        if r["event"] == "controller_state" and r["state"] == "Connected" and r["host_monotonic_ns"] > 15 * SECOND_NS:
            r["host_monotonic_ns"] = int(18.1 * SECOND_NS)
            r["reason"] = "clock synchronized"
    result = run(tmp_path, records)
    assert result.returncode == 1
    assert "FAIL  Connected after fresh sync" in result.stdout
