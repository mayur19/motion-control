"""Tests for tools/capture-labels.py (TMB-029 label listing and correction)."""
import hashlib
import json
import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).with_name("capture-labels.py")


def make_capture(tmp_path: pathlib.Path) -> pathlib.Path:
    capture = tmp_path / "cap_test"
    capture.mkdir()
    raw = capture / "raw.jsonl"
    raw.write_text('{"record":"capture_header","capture_format":1,"capture_id":"cap_test"}\n', encoding="utf-8")
    (capture / "raw.sha256").write_text(f"{hashlib.sha256(raw.read_bytes()).hexdigest()}  raw.jsonl\n")
    takes = [
        {"record": "labels_header", "capture_format": 1, "capture_id": "cap_test"},
        {"record": "take", "take_id": 1, "revision": 1, "player": 1, "phone": "iPhone",
         "handedness": "right", "intended_shot": "smash", "valid": True,
         "start_arrival_ns": 1, "end_arrival_ns": 2},
        {"record": "take", "take_id": 2, "revision": 1, "player": 2, "phone": "Galaxy",
         "handedness": "left", "intended_shot": "idle", "valid": True,
         "start_arrival_ns": 3, "end_arrival_ns": 4},
    ]
    (capture / "labels.jsonl").write_text("\n".join(json.dumps(t) for t in takes) + "\n", encoding="utf-8")
    return capture


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-I", str(SCRIPT), *args], capture_output=True, text=True)


def test_list_shows_effective_labels(tmp_path: pathlib.Path) -> None:
    capture = make_capture(tmp_path)
    result = run("list", str(capture))
    assert result.returncode == 0, result.stderr
    assert "take 1 rev 1" in result.stdout and "smash" in result.stdout
    assert "take 2 rev 1" in result.stdout


def test_correct_appends_revision_without_touching_raw(tmp_path: pathlib.Path) -> None:
    capture = make_capture(tmp_path)
    raw_before = (capture / "raw.jsonl").read_bytes()
    labels_before = (capture / "labels.jsonl").read_text(encoding="utf-8")
    result = run("correct", str(capture), "--take", "1", "--set", "intended_shot=clear", "--set", "valid=false")
    assert result.returncode == 0, result.stderr
    labels_after = (capture / "labels.jsonl").read_text(encoding="utf-8")
    assert labels_after.startswith(labels_before), "existing label records must be kept"
    last = json.loads(labels_after.strip().splitlines()[-1])
    assert last["take_id"] == 1 and last["revision"] == 2
    assert last["intended_shot"] == "clear" and last["valid"] is False
    assert last["start_arrival_ns"] == 1 and last["phone"] == "iPhone"
    assert (capture / "raw.jsonl").read_bytes() == raw_before
    listing = run("list", str(capture)).stdout
    assert "take 1 rev 2" in listing and "clear" in listing


def test_correct_rejects_invalid_values(tmp_path: pathlib.Path) -> None:
    capture = make_capture(tmp_path)
    before = (capture / "labels.jsonl").read_text(encoding="utf-8")
    for bad in ("intended_shot=backflip", "player=3", "handedness=both", "raw_acceleration=1", "valid=maybe"):
        result = run("correct", str(capture), "--take", "1", "--set", bad)
        assert result.returncode == 2, bad
    assert run("correct", str(capture), "--take", "9", "--set", "valid=false").returncode == 2
    assert (capture / "labels.jsonl").read_text(encoding="utf-8") == before


def test_verify_reports_checksum(tmp_path: pathlib.Path) -> None:
    capture = make_capture(tmp_path)
    assert run("verify", str(capture)).returncode == 0
    with (capture / "raw.jsonl").open("a", encoding="utf-8") as handle:
        handle.write('{"record":"datagram"}\n')
    result = run("verify", str(capture))
    assert result.returncode == 1 and "mismatch" in result.stdout
