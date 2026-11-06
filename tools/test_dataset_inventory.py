"""Synthetic-capture tests for tools/dataset-inventory.py (TMB-030)."""
import hashlib
import json
import pathlib
import subprocess
import sys

SCRIPT = pathlib.Path(__file__).with_name("dataset-inventory.py")
MIN = 60_000_000_000  # one minute in ns


def take(take_id: int, shot: str, *, phone: str = "iPhone", swings: int = 0, minutes: float = 0.5,
         valid: bool = True, hand: str = "right", speed: str = "none", player: int = 1,
         revision: int = 1) -> dict:
    start = take_id * 10 * MIN
    return {"record": "take", "take_id": take_id, "revision": revision, "player": player, "phone": phone,
            "handedness": hand, "intended_shot": shot, "valid": valid, "speed": speed,
            "swing_count": swings, "start_arrival_ns": start, "end_arrival_ns": start + int(minutes * MIN)}


def capture(root: pathlib.Path, capture_id: str, takes: list[dict], metadata: dict | None = None) -> pathlib.Path:
    directory = root / capture_id
    directory.mkdir(parents=True)
    header = {"record": "capture_header", "capture_format": 1, "capture_id": capture_id,
              "metadata": metadata or {"source": "host capture panel"}}
    raw = directory / "raw.jsonl"
    raw.write_text(json.dumps(header) + '\n{"record":"datagram","bytes_b64":"AA=="}\n', encoding="utf-8")
    (directory / "raw.sha256").write_text(f"{hashlib.sha256(raw.read_bytes()).hexdigest()}  raw.jsonl\n")
    lines = [{"record": "labels_header", "capture_format": 1, "capture_id": capture_id}, *takes]
    (directory / "labels.jsonl").write_text("\n".join(json.dumps(x) for x in lines) + "\n", encoding="utf-8")
    return directory


def build(tmp_path: pathlib.Path) -> pathlib.Path:
    root = tmp_path / "captures"
    capture(root, "cap_s1", [take(1, "smash", swings=30, speed="normal"), take(2, "clear", swings=25, speed="gentle"),
                             take(3, "drop", swings=5, valid=False), take(4, "handling", minutes=1.0)])
    capture(root, "cap_n1", [take(1, "idle", minutes=2.0), take(2, "walking", minutes=1.5)])
    capture(root, "cap_s4", [take(1, "lift", swings=28, hand="left", speed="fast"), take(2, "idle", minutes=1.0),
                             take(1, "lift", swings=27, hand="left", speed="fast", revision=2)])
    capture(root, "cap_g1", [take(1, "smash", phone="Galaxy", swings=20)])
    capture(root, "cap_extra", [take(1, "idle", minutes=1.0)])
    (root / "dataset-splits.json").write_text(json.dumps({
        "format": 1, "sessions": {"cap_s1": "tune", "cap_n1": "tune", "cap_s4": "heldout", "cap_g1": "tune"},
    }), encoding="utf-8")
    return root


def run(root: pathlib.Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-I", str(SCRIPT), str(root), *args], capture_output=True, text=True)


def report(tmp_path: pathlib.Path, root: pathlib.Path, *args: str) -> dict:
    out = tmp_path / "inventory.json"
    result = run(root, "--json", str(out), "--markdown", str(tmp_path / "inventory.md"), *args)
    assert result.returncode == 0, result.stderr
    return json.loads(out.read_text(encoding="utf-8"))


def test_counts_valid_swings_and_nonswing_minutes_per_phone(tmp_path: pathlib.Path) -> None:
    data = report(tmp_path, build(tmp_path))
    iphone = data["phones"]["iPhone"]
    assert iphone["swings"] == 30 + 25 + 27  # invalid take excluded, latest revision used
    assert iphone["swings_by_shot"] == {"clear": 25, "lift": 27, "smash": 30}
    assert iphone["swings_by_split"] == {"heldout": 27, "tune": 55}
    assert iphone["swings_by_hand"] == {"left": 27, "right": 55}
    assert iphone["swings_by_speed"] == {"fast": 27, "gentle": 25, "normal": 30}
    assert iphone["excluded_takes"] == 1 and iphone["excluded_swings"] == 5
    assert iphone["nonswing_minutes"] == 6.5  # extra 1.0 min idle is unassigned but still counted
    assert iphone["nonswing_minutes_by_split"] == {"heldout": 1.0, "tune": 4.5, "unassigned": 1.0}
    assert data["phones"]["Galaxy"]["swings"] == 20


def test_reports_gaps_against_minimums(tmp_path: pathlib.Path) -> None:
    data = report(tmp_path, build(tmp_path))
    gaps = "\n".join(data["gaps"])
    assert "iPhone: 82 of 100 swings" in gaps
    assert "iPhone: 6.5 of 20 non-swing minutes" in gaps
    assert "Galaxy: no held-out swing session" in gaps
    assert "cap_extra is not assigned" in gaps
    assert "only player 1" in gaps
    assert data["meets_minimums"] is False
    relaxed = report(tmp_path, build(tmp_path / "b"), "--min-swings", "20", "--min-nonswing-minutes", "0")
    assert not any("swings" in gap and " of " in gap for gap in relaxed["gaps"])


def test_checksums_listed_and_tampering_flagged(tmp_path: pathlib.Path) -> None:
    root = build(tmp_path)
    with (root / "cap_g1" / "raw.jsonl").open("a", encoding="utf-8") as handle:
        handle.write("{}\n")
    data = report(tmp_path, root)
    checks = {c["capture_id"]: c for c in data["captures"]}
    assert checks["cap_s1"]["raw_verified"] is True and len(checks["cap_s1"]["raw_sha256"]) == 64
    assert checks["cap_g1"]["raw_verified"] is False
    assert any("cap_g1 raw checksum mismatch" in gap for gap in data["gaps"])
    markdown = (tmp_path / "inventory.md").read_text(encoding="utf-8")
    assert "cap_s1" in markdown and "Coverage gaps" in markdown


def test_flags_unexpected_metadata_for_privacy_review(tmp_path: pathlib.Path) -> None:
    root = build(tmp_path)
    capture(root, "cap_meta", [take(1, "idle")], metadata={"source": "x", "owner_email": "a@b.c"})
    data = report(tmp_path, root)
    assert any("cap_meta metadata field owner_email" in item for item in data["privacy_review"])


def test_split_file_rejects_unknown_split(tmp_path: pathlib.Path) -> None:
    root = build(tmp_path)
    (root / "dataset-splits.json").write_text(json.dumps({"format": 1, "sessions": {"cap_s1": "train"}}))
    result = run(root, "--json", str(tmp_path / "x.json"))
    assert result.returncode == 2 and "tune or heldout" in result.stderr


def test_excluded_sessions_are_kept_but_not_counted(tmp_path: pathlib.Path) -> None:
    root = build(tmp_path)
    splits = json.loads((root / "dataset-splits.json").read_text(encoding="utf-8"))
    splits["sessions"]["cap_extra"] = "exclude"
    (root / "dataset-splits.json").write_text(json.dumps(splits), encoding="utf-8")
    data = report(tmp_path, root)
    assert data["phones"]["iPhone"]["nonswing_minutes"] == 5.5
    assert not any("cap_extra" in gap for gap in data["gaps"])
    assert {c["capture_id"]: c["split"] for c in data["captures"]}["cap_extra"] == "exclude"
