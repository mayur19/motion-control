#!/usr/bin/env python3
"""TMB-033 detector evaluation over labeled capture replay results.

By default this runs the Godot replay pipeline for the selected split. Existing
replay JSON and series JSONL can instead be supplied with --results-dir; files
must be named <capture_id>.json and <capture_id>.series.jsonl.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess
import sys
import tempfile
from collections import defaultdict

SWING_SHOTS = {"smash", "clear", "drop", "lift", "other_swing"}
NONSWING_SHOTS = {"idle", "handling", "walking"}
SPLITS = {"tune", "heldout", "exclude"}
NS_PER_MINUTE = 60_000_000_000
PEAK_SEARCH_NS = 1_000_000_000
LABEL_FIELDS = ("player", "phone", "handedness", "intended_shot", "valid", "speed", "swing_count")


class EvaluationError(ValueError):
    """Inputs cannot produce a trustworthy report."""


class Metrics:
    def __init__(self) -> None:
        self.true_positives = 0
        self.false_negatives = 0
        self.false_positives = 0
        self.expected_swings = 0
        self.detector_events = 0
        self.non_swing_ns = 0
        self.non_swing_false_positives = 0
        self.timings: list[float] = []

    def add(self, item: dict) -> None:
        self.true_positives += item["true_positives"]
        self.false_negatives += item["false_negatives"]
        self.false_positives += item["false_positives"]
        self.expected_swings += item["expected_swings"]
        self.detector_events += item["detector_events"]
        self.non_swing_ns += item["non_swing_ns"]
        self.non_swing_false_positives += item["non_swing_false_positives"]
        self.timings.extend(item["trigger_peak_timing_ms"])

    def as_dict(self) -> dict:
        recall_denominator = self.true_positives + self.false_negatives
        precision_denominator = self.true_positives + self.false_positives
        minutes = self.non_swing_ns / NS_PER_MINUTE
        return {
            "true_positives": self.true_positives,
            "false_negatives": self.false_negatives,
            "false_positives": self.false_positives,
            "expected_swings": self.expected_swings,
            "detector_events": self.detector_events,
            "recall": self.true_positives / recall_denominator if recall_denominator else None,
            "precision": self.true_positives / precision_denominator if precision_denominator else None,
            "non_swing_minutes": round(minutes, 6),
            "false_triggers_per_10_minutes": (
                round(self.non_swing_false_positives * 10 / minutes, 6) if minutes else None
            ),
            "trigger_peak_timing_ms": timing_summary(self.timings),
        }


def timing_summary(values: list[float]) -> dict:
    if not values:
        return {"count": 0, "mean": None, "median": None, "minimum": None, "maximum": None}
    return {
        "count": len(values),
        "mean": round(statistics.fmean(values), 3),
        "median": round(statistics.median(values), 3),
        "minimum": round(min(values), 3),
        "maximum": round(max(values), 3),
    }


def read_splits(root: pathlib.Path) -> dict[str, str]:
    path = root / "dataset-splits.json"
    if not path.is_file():
        raise EvaluationError(f"missing {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise EvaluationError(f"invalid dataset-splits.json: {error}") from error
    sessions = data.get("sessions") if isinstance(data, dict) else None
    if not isinstance(sessions, dict):
        raise EvaluationError("dataset-splits.json sessions must be an object")
    result: dict[str, str] = {}
    for capture_id, split in sessions.items():
        if not isinstance(capture_id, str) or split not in SPLITS:
            raise EvaluationError(f"invalid split assignment {capture_id!r}: {split!r}")
        result[capture_id] = split
    discovered = {
        path.name for path in root.iterdir()
        if path.is_dir() and (path / "labels.jsonl").is_file() and (path / "raw.jsonl").is_file()
    }
    unassigned = sorted(discovered - set(result))
    if unassigned:
        raise EvaluationError(f"captures missing split assignments: {', '.join(unassigned)}")
    missing = sorted(set(result) - discovered)
    if missing:
        raise EvaluationError(f"split assignments missing capture directories: {', '.join(missing)}")
    return result


def effective_takes(capture: pathlib.Path) -> list[dict]:
    path = capture / "labels.jsonl"
    if not path.is_file():
        raise EvaluationError(f"missing {path}")
    latest: dict[int, dict] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue  # append-only files may end with a torn line
        if isinstance(record, dict) and record.get("record") == "take":
            take_id = int(record.get("take_id", 0))
            if take_id not in latest or int(record.get("revision", 0)) >= int(latest[take_id].get("revision", 0)):
                latest[take_id] = record
    return [latest[take_id] for take_id in sorted(latest)]


def raw_checksum(capture: pathlib.Path) -> str:
    raw = capture / "raw.jsonl"
    sidecar = capture / "raw.sha256"
    if not raw.is_file() or not sidecar.is_file():
        raise EvaluationError(f"{capture.name}: missing raw.jsonl or raw.sha256")
    actual = hashlib.sha256(raw.read_bytes()).hexdigest()
    expected = sidecar.read_text(encoding="utf-8").split()[0]
    if actual != expected:
        raise EvaluationError(f"{capture.name}: raw checksum verification failed")
    return actual


def read_json(path: pathlib.Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvaluationError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise EvaluationError(f"{path}: expected a JSON object")
    return value


def read_series(path: pathlib.Path) -> list[dict]:
    if not path.is_file():
        raise EvaluationError(f"missing replay series {path}")
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise EvaluationError(f"{path}:{number}: {error}") from error
        if not isinstance(row, dict) or "arrival_monotonic_ns" not in row:
            raise EvaluationError(f"{path}:{number}: series must include arrival_monotonic_ns")
        rows.append(row)
    return rows


def validate_replay(capture: pathlib.Path, result: dict, takes: list[dict], digest: str) -> None:
    capture_id = capture.name
    if not result.get("ok") or int(result.get("result_format", 0)) != 1:
        raise EvaluationError(f"{capture_id}: unsupported or failed replay result")
    if result.get("capture_id") != capture_id:
        raise EvaluationError(f"{capture_id}: replay capture_id mismatch")
    if not result.get("raw_verified") or result.get("raw_sha256") != digest:
        raise EvaluationError(f"{capture_id}: replay checksum does not match the current raw capture")
    replay_takes = {int(item.get("take_id", 0)): item for item in result.get("takes", [])}
    if set(replay_takes) != {int(item.get("take_id", 0)) for item in takes}:
        raise EvaluationError(f"{capture_id}: replay has stale labels (take set differs)")
    for take in takes:
        take_id = int(take["take_id"])
        replay_take = replay_takes[take_id]
        labels = replay_take.get("labels", {})
        if int(replay_take.get("label_revision", 0)) != int(take.get("revision", 0)):
            raise EvaluationError(f"{capture_id} take {take_id}: replay has stale labels (revision differs)")
        for field in LABEL_FIELDS:
            expected = take.get(field, "none" if field == "speed" else 0 if field == "swing_count" else None)
            if labels.get(field, "none" if field == "speed" else 0 if field == "swing_count" else None) != expected:
                raise EvaluationError(f"{capture_id} take {take_id}: replay has stale labels ({field} differs)")
        if int(replay_take.get("start_arrival_ns", 0)) != int(take.get("start_arrival_ns", 0)) or \
                int(replay_take.get("end_arrival_ns", 0)) != int(take.get("end_arrival_ns", 0)):
            raise EvaluationError(f"{capture_id} take {take_id}: replay has stale labels (boundaries differ)")


def events_in_take(result: dict, take: dict) -> list[dict]:
    start = int(take["start_arrival_ns"])
    finish = int(take["end_arrival_ns"])
    return sorted(
        (event for event in result.get("events", [])
         if start <= int(event.get("arrival_monotonic_ns", -1)) <= finish),
        key=lambda event: int(event.get("sensor_monotonic_ns", 0)),
    )


def trigger_peak_timings(events: list[dict], series: list[dict], take: dict) -> list[float]:
    """Trigger-to-following-peak estimate; positive values mean trigger lead."""
    start = int(take["start_arrival_ns"])
    finish = int(take["end_arrival_ns"])
    timings = []
    for index, event in enumerate(events):
        controller = int(event.get("controller_id", 0))
        trigger_ns = int(event.get("sensor_monotonic_ns", 0))
        next_trigger_ns = None
        for later in events[index + 1:]:
            if int(later.get("controller_id", 0)) == controller:
                next_trigger_ns = int(later.get("sensor_monotonic_ns", 0))
                break
        upper = trigger_ns + PEAK_SEARCH_NS
        if next_trigger_ns is not None:
            upper = min(upper, next_trigger_ns - 1)
        candidates = [
            row for row in series
            if int(row.get("controller_id", 0)) == controller
            and trigger_ns <= int(row.get("sensor_monotonic_ns", -1)) <= upper
            and start <= int(row.get("arrival_monotonic_ns", -1)) <= finish
        ]
        if candidates:
            peak = max(candidates, key=lambda row: float(row.get("preprocessed_angular_speed", 0.0)))
            delta_ms = (int(peak["sensor_monotonic_ns"]) - trigger_ns) / 1_000_000
            timings.append(round(delta_ms, 3))
    return timings


def take_metrics(take: dict, events: list[dict], timings: list[float]) -> dict:
    shot = str(take.get("intended_shot", ""))
    count = len(events)
    duration_ns = max(0, int(take["end_arrival_ns"]) - int(take["start_arrival_ns"]))
    if shot in SWING_SHOTS:
        expected = int(take.get("swing_count", 0))
        true_positives = min(expected, count)
        false_negatives = max(0, expected - count)
        false_positives = max(0, count - expected)
        non_swing_ns = 0
        non_swing_false_positives = 0
    elif shot in NONSWING_SHOTS:
        expected = 0
        true_positives = 0
        false_negatives = 0
        false_positives = count
        non_swing_ns = duration_ns
        non_swing_false_positives = count
    else:
        raise EvaluationError(f"take {take.get('take_id')}: unknown intended_shot {shot!r}")
    return {
        "true_positives": true_positives,
        "false_negatives": false_negatives,
        "false_positives": false_positives,
        "expected_swings": expected,
        "detector_events": count,
        "non_swing_ns": non_swing_ns,
        "non_swing_false_positives": non_swing_false_positives,
        "trigger_peak_timing_ms": timings,
    }


def evaluate(root: pathlib.Path, results_dir: pathlib.Path, split: str) -> dict:
    root = pathlib.Path(root)
    results_dir = pathlib.Path(results_dir)
    if split not in {"tune", "heldout"}:
        raise EvaluationError("report split must be tune or heldout")
    splits = read_splits(root)
    selected = sorted(capture_id for capture_id, assigned in splits.items() if assigned == split)
    if not selected:
        raise EvaluationError(f"no captures assigned to {split}")

    aggregate = Metrics()
    breakdowns: dict[str, dict[str, Metrics]] = {
        dimension: defaultdict(Metrics) for dimension in ("phone", "player", "hand", "shot", "speed")
    }
    report_takes = []
    invalid_takes = []
    detector = None

    for capture_id in selected:
        capture = root / capture_id
        digest = raw_checksum(capture)
        takes = effective_takes(capture)
        result = read_json(results_dir / f"{capture_id}.json")
        validate_replay(capture, result, takes, digest)
        current_detector = result.get("detector")
        if not isinstance(current_detector, dict):
            raise EvaluationError(f"{capture_id}: replay omitted DetectorPipeline.describe()")
        if detector is None:
            detector = current_detector
        elif current_detector != detector:
            raise EvaluationError(f"{capture_id}: pipeline configuration differs from other replay results")
        series = read_series(results_dir / f"{capture_id}.series.jsonl")
        for take in takes:
            take_id = int(take["take_id"])
            events = events_in_take(result, take)
            if not bool(take.get("valid", False)):
                invalid_takes.append({"capture_id": capture_id, "take_id": take_id,
                                      "revision": int(take.get("revision", 0)),
                                      "reason": "valid=false", "labels": {field: take.get(field) for field in LABEL_FIELDS},
                                      "detector_events": len(events)})
                continue
            timings = trigger_peak_timings(events, series, take)
            metrics = take_metrics(take, events, timings)
            aggregate.add(metrics)
            keys = {
                "phone": str(take.get("phone", "")),
                "player": str(take.get("player", "")),
                "hand": str(take.get("handedness", "")),
                "shot": str(take.get("intended_shot", "")),
                "speed": str(take.get("speed", "none")),
            }
            for dimension, key in keys.items():
                breakdowns[dimension][key].add(metrics)
            public_metrics = {
                key: value for key, value in metrics.items()
                if key not in {"non_swing_ns", "non_swing_false_positives"}
            }
            report_takes.append({
                "capture_id": capture_id, "take_id": take_id,
                "label_revision": int(take.get("revision", 0)),
                "labels": {field: take.get(field, "none" if field == "speed" else 0) for field in LABEL_FIELDS},
                "duration_minutes": round(max(0, int(take["end_arrival_ns"]) - int(take["start_arrival_ns"]))
                                          / NS_PER_MINUTE, 6),
                **public_metrics,
            })

    return {
        "evaluation_format": 1,
        "split": split,
        "captures": selected,
        "detector": detector,
        "matching_rule": {
            "name": "count_based_per_take",
            "description": "TP=min(expected swings, triggers); FN=max(expected-triggers, 0); "
                           "FP=max(triggers-expected, 0). Every trigger in a non-swing take is an FP.",
            "limitation": "Swing labels contain counts, not per-swing timestamps; individual triggers cannot be "
                          "matched to specific swings, and a miss plus an extra trigger can cancel in the count.",
        },
        "trigger_peak_method": {
            "description": "For each trigger, select the maximum preprocessed angular speed after that trigger, "
                           "before the next trigger from the same controller, take end, or 1000 ms.",
            "sign": "Positive milliseconds mean the trigger leads the following peak.",
            "limitation": "This is an event-to-signal estimate, not ground-truth swing timing. Extra triggers, "
                          "backswing peaks and missing per-swing timestamps can associate the wrong peak; "
                          "lag after an already-passed physical peak is not observable with this rule.",
        },
        "aggregate": aggregate.as_dict(),
        "breakdowns": {
            dimension: {key: metrics.as_dict() for key, metrics in sorted(groups.items())}
            for dimension, groups in breakdowns.items()
        },
        "takes": report_takes,
        "excluded": {
            "invalid_takes": invalid_takes,
            "exclude_sessions": sorted(capture_id for capture_id, assigned in splits.items() if assigned == "exclude"),
        },
    }


def metric_text(value: object) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.3f}".rstrip("0").rstrip(".")
    return str(value)


def markdown(report: dict) -> str:
    aggregate = report["aggregate"]
    lines = [
        f"# TMB-033 detector evaluation — {report['split']}", "",
        "This report is computed evidence for the named dataset split. Synthetic fixture results are not physical evidence.", "",
        "## Pipeline configuration", "", "```json", json.dumps(report["detector"], indent=2, sort_keys=True), "```", "",
        "## Count-based matching", "", report["matching_rule"]["description"], "", report["matching_rule"]["limitation"], "",
        "## Overall metrics", "",
        "| TP | FN | FP | Recall | Precision | Non-swing min | False triggers / 10 min |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        f"| {aggregate['true_positives']} | {aggregate['false_negatives']} | {aggregate['false_positives']} | "
        f"{metric_text(aggregate['recall'])} | {metric_text(aggregate['precision'])} | "
        f"{metric_text(aggregate['non_swing_minutes'])} | {metric_text(aggregate['false_triggers_per_10_minutes'])} |", "",
        "## Per-take metrics", "",
        "| Capture | Take | Shot | Expected | Events | TP | FN | FP | Median trigger-to-peak ms |",
        "| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for take in report["takes"]:
        timing = timing_summary(take["trigger_peak_timing_ms"])
        lines.append(f"| {take['capture_id']} | {take['take_id']} | {take['labels']['intended_shot']} | "
                     f"{take['expected_swings']} | {take['detector_events']} | {take['true_positives']} | "
                     f"{take['false_negatives']} | {take['false_positives']} | {metric_text(timing['median'])} |")
    lines += ["", "## Subgroups", "",
              "Every available phone, player, hand, shot and speed subgroup is shown below.", ""]
    for dimension, groups in report["breakdowns"].items():
        lines += [f"### {dimension.title()}", "",
                  "| Value | TP | FN | FP | Recall | Precision | False triggers / 10 min |",
                  "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
        for key, metrics in groups.items():
            lines.append(f"| {key} | {metrics['true_positives']} | {metrics['false_negatives']} | "
                         f"{metrics['false_positives']} | {metric_text(metrics['recall'])} | "
                         f"{metric_text(metrics['precision'])} | "
                         f"{metric_text(metrics['false_triggers_per_10_minutes'])} |")
        lines.append("")
    timing = aggregate["trigger_peak_timing_ms"]
    lines += [
        "## Trigger timing estimate", "", report["trigger_peak_method"]["description"], "",
        report["trigger_peak_method"]["sign"], "", report["trigger_peak_method"]["limitation"], "",
        f"Samples: {timing['count']}; mean {metric_text(timing['mean'])} ms; "
        f"median {metric_text(timing['median'])} ms; range "
        f"{metric_text(timing['minimum'])}–{metric_text(timing['maximum'])} ms.", "",
        "## Exclusions", "",
        f"Exclude-split sessions: {', '.join(report['excluded']['exclude_sessions']) or 'none'}.", "",
    ]
    if report["excluded"]["invalid_takes"]:
        lines += ["Invalid takes (not included in metrics):", ""]
        for item in report["excluded"]["invalid_takes"]:
            lines.append(f"- {item['capture_id']} take {item['take_id']} revision {item['revision']} (`valid=false`)")
    else:
        lines.append("Invalid takes: none.")
    return "\n".join(lines) + "\n"


def run_replays(root: pathlib.Path, split: str, output: pathlib.Path, config: pathlib.Path | None,
                godot: str, project: pathlib.Path) -> None:
    assignments = read_splits(root)
    config_path = config.resolve() if config is not None else None
    for capture_id in sorted(item for item, assigned in assignments.items() if assigned == split):
        command = [godot, "--headless", "--path", str(project), "--script", "res://replay/replay_capture.gd", "--",
                   f"--capture={root / capture_id}", f"--output={output / (capture_id + '.json')}",
                   f"--series={output / (capture_id + '.series.jsonl')}"]
        if config_path is not None:
            command.append(f"--config={config_path}")
        completed = subprocess.run(command, capture_output=True, text=True)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            raise EvaluationError(f"replay failed for {capture_id}: {detail}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", type=pathlib.Path, help="capture root containing dataset-splits.json")
    parser.add_argument("--split", choices=("tune", "heldout"), default="tune")
    parser.add_argument("--results-dir", type=pathlib.Path,
                        help="read existing <capture_id>.json and .series.jsonl replay outputs")
    parser.add_argument("--config", type=pathlib.Path, help="detector config passed to replay (auto-replay mode)")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parents[1] / "apps/host-godot")
    parser.add_argument("--confirm-heldout", action="store_true",
                        help="acknowledge that held-out evaluation is a deliberate one-time run")
    parser.add_argument("--json", type=pathlib.Path)
    parser.add_argument("--markdown", type=pathlib.Path)
    args = parser.parse_args(argv)
    if args.split == "heldout" and not args.confirm_heldout:
        parser.error("heldout evaluation requires --confirm-heldout after the detector configuration is frozen")
    if args.split == "heldout" and (args.json is None or args.markdown is None):
        parser.error("heldout evaluation requires both --json and --markdown archive paths")
    if args.split == "heldout":
        existing = [str(path) for path in (args.json, args.markdown) if path.exists()]
        if existing:
            parser.error(f"heldout archive already exists: {', '.join(existing)}")
    if not args.root.is_dir():
        parser.error(f"capture root not found: {args.root}")
    try:
        if args.results_dir:
            if args.config:
                raise EvaluationError("--config cannot be combined with --results-dir; config comes from replay output")
            report = evaluate(args.root, args.results_dir, args.split)
        else:
            with tempfile.TemporaryDirectory(prefix="tmb-033-replay-") as temporary:
                replay_dir = pathlib.Path(temporary)
                run_replays(args.root, args.split, replay_dir, args.config, args.godot, args.project)
                report = evaluate(args.root, replay_dir, args.split)
    except EvaluationError as error:
        print(f"Evaluation error: {error}", file=sys.stderr)
        return 2
    if args.json:
        args.json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(markdown(report), encoding="utf-8")
    metrics = report["aggregate"]
    print(f"TMB-033_EVALUATION split={args.split} captures={len(report['captures'])} "
          f"tp={metrics['true_positives']} fn={metrics['false_negatives']} fp={metrics['false_positives']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
