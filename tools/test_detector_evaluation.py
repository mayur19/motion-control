"""Synthetic tests for the TMB-033 detector evaluation report."""
import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys

import pytest

SCRIPT = pathlib.Path(__file__).with_name("detector-evaluation.py")
NS_PER_MINUTE = 60_000_000_000


def load_module():
    spec = importlib.util.spec_from_file_location("detector_evaluation", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def label(take_id: int, shot: str, *, start_minute: float, duration_minutes: float = 0.1,
          swings: int = 0, revision: int = 1, valid: bool = True, phone: str = "iPhone",
          player: int = 1, hand: str = "right", speed: str = "normal") -> dict:
    start = int(start_minute * NS_PER_MINUTE)
    return {
        "record": "take", "take_id": take_id, "revision": revision,
        "player": player, "phone": phone, "handedness": hand,
        "intended_shot": shot, "speed": speed, "swing_count": swings,
        "valid": valid, "start_arrival_ns": start,
        "end_arrival_ns": start + int(duration_minutes * NS_PER_MINUTE),
    }


def capture(root: pathlib.Path, capture_id: str, labels: list[dict]) -> str:
    directory = root / capture_id
    directory.mkdir(parents=True)
    raw = directory / "raw.jsonl"
    raw.write_text(json.dumps({"record": "capture_header", "capture_format": 1,
                               "capture_id": capture_id}) + "\n", encoding="utf-8")
    digest = hashlib.sha256(raw.read_bytes()).hexdigest()
    (directory / "raw.sha256").write_text(f"{digest}  raw.jsonl\n", encoding="utf-8")
    records = [{"record": "labels_header", "capture_format": 1, "capture_id": capture_id}, *labels]
    (directory / "labels.jsonl").write_text(
        "\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8"
    )
    return digest


def described_config(onset: float = 3.0) -> dict:
    return {
        "detector": "early_rise", "version": 1,
        "config": {"onset_speed_rad_s": onset},
        "preprocessing": {"name": "one_pole_lowpass", "version": 1,
                          "config": {"cutoff_hz": 25.0, "max_gap_ms": 50.0}},
    }


def replay(results: pathlib.Path, capture_id: str, digest: str, labels: list[dict],
           event_times: dict[int, list[float]], *, detector: dict | None = None) -> None:
    takes = []
    events = []
    sequence = 1
    for item in labels:
        start = int(item["start_arrival_ns"])
        end = int(item["end_arrival_ns"])
        takes.append({
            "take_id": item["take_id"], "label_revision": item["revision"],
            "labels": {key: item[key] for key in (
                "player", "phone", "handedness", "intended_shot", "valid", "speed", "swing_count"
            )},
            "start_arrival_ns": start, "end_arrival_ns": end,
            "event_count": len(event_times.get(item["take_id"], [])),
        })
        for offset_ms in event_times.get(item["take_id"], []):
            timestamp = start + int(offset_ms * 1_000_000)
            events.append({"detector": "early_rise", "controller_id": 7, "sequence": sequence,
                           "sensor_monotonic_ns": timestamp, "arrival_monotonic_ns": timestamp})
            sequence += 1
    result = {
        "ok": True, "result_format": 1, "capture_id": capture_id,
        "raw_sha256": digest, "raw_verified": True,
        "detector": detector or described_config(), "takes": takes, "events": events,
        "totals": {"takes": len(takes), "events": len(events)},
    }
    (results / f"{capture_id}.json").write_text(json.dumps(result), encoding="utf-8")
    rows = []
    for event in events:
        event_ns = event["sensor_monotonic_ns"]
        # The maximum following speed is 120 ms after each synthetic trigger.
        rows.extend([
            {"controller_id": 7, "sensor_monotonic_ns": event_ns,
             "arrival_monotonic_ns": event["arrival_monotonic_ns"],
             "preprocessed_angular_speed": 3.0},
            {"controller_id": 7, "sensor_monotonic_ns": event_ns + 120_000_000,
             "arrival_monotonic_ns": event["arrival_monotonic_ns"] + 120_000_000,
             "preprocessed_angular_speed": 8.0},
        ])
    (results / f"{capture_id}.series.jsonl").write_text(
        "\n".join(json.dumps(row) for row in rows) + ("\n" if rows else ""), encoding="utf-8"
    )


def fixture(tmp_path: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    root = tmp_path / "captures"
    results = tmp_path / "results"
    results.mkdir(parents=True)
    tune_labels = [
        label(1, "smash", start_minute=0, swings=3, speed="fast"),
        label(2, "clear", start_minute=1, swings=1, speed="gentle", hand="left"),
        label(3, "handling", start_minute=2, duration_minutes=5, speed="none"),
        label(4, "drop", start_minute=8, swings=9, valid=False),
        # Latest revision is authoritative and changes the count from 8 to 2.
        label(5, "lift", start_minute=9, swings=8, revision=1),
        label(5, "lift", start_minute=9, swings=2, revision=2),
    ]
    digest = capture(root, "cap_tune", tune_labels)
    effective = [*tune_labels[:4], tune_labels[-1]]
    replay(results, "cap_tune", digest, effective,
           {1: [100, 500], 2: [100, 400], 3: [100, 500], 4: [100], 5: [100, 400]})

    heldout_labels = [label(1, "smash", start_minute=0, swings=2, phone="Galaxy", player=2)]
    digest = capture(root, "cap_heldout", heldout_labels)
    replay(results, "cap_heldout", digest, heldout_labels, {1: [100, 400]})

    excluded_labels = [label(1, "idle", start_minute=0, duration_minutes=1, speed="none")]
    capture(root, "cap_excluded", excluded_labels)
    (root / "dataset-splits.json").write_text(json.dumps({
        "format": 1,
        "sessions": {"cap_tune": "tune", "cap_heldout": "heldout", "cap_excluded": "exclude"},
    }), encoding="utf-8")
    return root, results


def test_count_matching_metrics_breakdowns_and_exclusions(tmp_path: pathlib.Path) -> None:
    module = load_module()
    root, results = fixture(tmp_path)
    report = module.evaluate(root, results, "tune")

    # Swing takes: (2/3), (1/1 + one over-trigger), (2/2). Non-swing: two false triggers.
    assert report["aggregate"] == {
        "true_positives": 5, "false_negatives": 1, "false_positives": 3,
        "expected_swings": 6, "detector_events": 8,
        "recall": pytest.approx(5 / 6), "precision": pytest.approx(5 / 8),
        "non_swing_minutes": 5.0, "false_triggers_per_10_minutes": 4.0,
        "trigger_peak_timing_ms": {"count": 8, "mean": 120.0, "median": 120.0,
                                     "minimum": 120.0, "maximum": 120.0},
    }
    assert report["breakdowns"]["phone"]["iPhone"]["recall"] == pytest.approx(5 / 6)
    assert report["breakdowns"]["hand"]["left"]["false_positives"] == 1
    assert report["breakdowns"]["shot"]["handling"]["false_triggers_per_10_minutes"] == 4.0
    assert report["breakdowns"]["speed"]["fast"]["false_negatives"] == 1
    assert report["takes"][0]["true_positives"] == 2
    assert report["takes"][0]["false_negatives"] == 1
    assert report["takes"][0]["trigger_peak_timing_ms"] == [120.0, 120.0]
    assert report["excluded"]["invalid_takes"][0]["take_id"] == 4
    assert report["excluded"]["exclude_sessions"] == ["cap_excluded"]
    assert report["detector"] == described_config()


def test_splits_are_reported_separately_and_subgroups_are_not_inherited(tmp_path: pathlib.Path) -> None:
    module = load_module()
    root, results = fixture(tmp_path)
    tune = module.evaluate(root, results, "tune")
    heldout = module.evaluate(root, results, "heldout")
    assert tune["split"] == "tune" and tune["captures"] == ["cap_tune"]
    assert heldout["split"] == "heldout" and heldout["captures"] == ["cap_heldout"]
    assert set(tune["breakdowns"]["phone"]) == {"iPhone"}
    assert set(heldout["breakdowns"]["phone"]) == {"Galaxy"}
    assert heldout["aggregate"]["recall"] == 1.0


def test_rejects_stale_labels_checksum_and_mixed_pipeline_configs(tmp_path: pathlib.Path) -> None:
    module = load_module()
    root, results = fixture(tmp_path)
    data = json.loads((results / "cap_tune.json").read_text(encoding="utf-8"))
    data["takes"][0]["label_revision"] = 0
    (results / "cap_tune.json").write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(module.EvaluationError, match="stale labels"):
        module.evaluate(root, results, "tune")

    root, results = fixture(tmp_path / "checksum")
    data = json.loads((results / "cap_tune.json").read_text(encoding="utf-8"))
    data["raw_sha256"] = "0" * 64
    (results / "cap_tune.json").write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(module.EvaluationError, match="checksum"):
        module.evaluate(root, results, "tune")

    root, results = fixture(tmp_path / "config")
    extra = [label(1, "smash", start_minute=0, swings=1)]
    digest = capture(root, "cap_tune_2", extra)
    replay(results, "cap_tune_2", digest, extra, {1: [100]}, detector=described_config(4.0))
    splits = json.loads((root / "dataset-splits.json").read_text(encoding="utf-8"))
    splits["sessions"]["cap_tune_2"] = "tune"
    (root / "dataset-splits.json").write_text(json.dumps(splits), encoding="utf-8")
    with pytest.raises(module.EvaluationError, match="pipeline configuration"):
        module.evaluate(root, results, "tune")


def test_cli_requires_explicit_heldout_confirmation_and_writes_report(tmp_path: pathlib.Path) -> None:
    root, results = fixture(tmp_path)
    output = tmp_path / "heldout.json"
    command = [sys.executable, "-I", str(SCRIPT), str(root), "--results-dir", str(results),
               "--split", "heldout", "--json", str(output)]
    refused = subprocess.run(command, capture_output=True, text=True)
    assert refused.returncode == 2
    assert "--confirm-heldout" in refused.stderr
    unarchived = subprocess.run([*command, "--confirm-heldout"], capture_output=True, text=True)
    assert unarchived.returncode == 2
    assert "--json and --markdown" in unarchived.stderr
    accepted = subprocess.run([*command, "--confirm-heldout", "--markdown", str(tmp_path / "heldout.md")],
                              capture_output=True, text=True)
    assert accepted.returncode == 0, accepted.stderr
    assert "TMB-033_EVALUATION" in accepted.stdout
    saved = json.loads(output.read_text(encoding="utf-8"))
    assert saved["split"] == "heldout" and saved["detector"] == described_config()
    markdown = (tmp_path / "heldout.md").read_text(encoding="utf-8")
    assert "Count-based matching" in markdown and "Pipeline configuration" in markdown
    assert "Per-take metrics" in markdown and "cap_heldout" in markdown
    repeated = subprocess.run([*command, "--confirm-heldout", "--markdown", str(tmp_path / "heldout.md")],
                              capture_output=True, text=True)
    assert repeated.returncode == 2 and "already exists" in repeated.stderr
