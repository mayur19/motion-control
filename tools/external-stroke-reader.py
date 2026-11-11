#!/usr/bin/env python3
"""Read-only BadminSense BADS_CLL reader with descriptive, off-domain stroke statistics.

TMB-033 external-data spike (docs/external-dataset-evaluation.md). Reads the
published archive (.zip), an extracted folder or one section .json without
modifying it, validates the schema and the units confirmed in Section 6.1, and
reports only aggregate, placement-robust gyroscope descriptions: angular-speed
peak, 20 %-of-peak rise time, prior-peak ratio and data-quality flags.

The dataset is CC BY-NC-ND and this repository is public (MIT). Reports are
derived material: they may only be written outside the repository or into the
git-ignored external-data/ folder. Nothing here is detector or product evidence.

  external-stroke-reader.py SOURCE [--json OUT.json] [--markdown OUT.md]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import re
import sys
import zipfile
from collections import defaultdict
from dataclasses import dataclass

ADAPTER_VERSION = 1  # bump when parsing or a descriptive definition changes
DATASET = "BadminSense BADS_CLL"
DATASET_VERSION = "1.0 (BADS_CLL_OPENACCESS_V1)"
EXPECTED_SHA256 = "17ed260ac0fe4653e168e96d250663830f168d5a108f2f13f0563dce64e1c29a"
CITATION = ("T. Chen, K. Chen, X. Liu, P. Ke, Z. Sun. BadminSense: Enabling Fine-Grained Badminton Stroke "
            "Evaluation on a Single Smartwatch. CHI 2026. arXiv:2603.21825")
REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOWED_IN_REPO = REPO_ROOT / "external-data"

UNITS = {"timestamp": "ms (relative session clock)", "gyroscope": "rad/s",
         "accelerometer": "m/s^2 including gravity"}
STREAMS = {
    "ACCELEROMETER": ("Gx", "Gy", "Gz"),
    "GYROSCOPE": ("angularSpeedX", "angularSpeedY", "angularSpeedZ"),
}
INFO_KEYS = ("recordName", "exp", "section", "device", "startTimestamp", "endTimestamp")
RECORD_NAME = re.compile(r"^(Man|Woman|Women|Male|Female)_(Low|Medium|High)_([A-Za-z]+)_(Play\d+)_(\d+)_(\d+)$")

PARAMETERS = {
    "rise_fraction_of_peak": 0.2,
    "prior_peak_share_threshold": 0.3,
    "gap_limit_ms": 50,  # the product preprocessor's max_gap_ms
    "gyro_saturation_rad_s": 39.9,  # measured clip about 40.03 rad/s (Section 6.1)
    "accel_saturation_m_s2": 78.0,  # measured clip 78.41 m/s^2 = 8 g
    "max_plausible_gyro_rad_s": 70.0,  # beyond a 4000 deg/s range: values are not rad/s
    "plausible_median_accel_m_s2": [3.0, 60.0],  # gravity-inclusive m/s^2; values in g would be about 1
}
LIMITATIONS = [
    "External/off-domain: wrist-worn smartwatch (forearm) with real shuttle impact, not a phone held as the racket.",
    "Values are in watch sensor axes; no mapping to the common racket frame exists, so detector thresholds do not transfer.",
    "Strokes are pre-segmented 2000 ms windows of valid strokes only: no idle, handling or continuous data, so "
    "false triggers per 10 minutes and precision cannot be measured.",
    "Peaks in saturated strokes are clipped; peak values and peak timing are biased there.",
    "prior_peak_ratio (largest speed before the pre-rise valley / peak) is a candidate backswing indicator, "
    "not a validated backswing label.",
    "Not used: stroke quality ratings (not product ground truth), impact location, audio, GIFs, magnetometer, "
    "rotation vector.",
    "Not TMB-030 tune or held-out data, never merged with them, and not a physical or product performance claim.",
]


class StrokeFormatError(ValueError):
    """The source does not match the schema confirmed in Section 6.1."""


class UnitsError(ValueError):
    """Values contradict the units confirmed in Section 6.1."""


@dataclass(frozen=True)
class Stroke:
    record_name: str
    stroke_type: str
    experience: str
    player: str
    section: int
    device: str
    start_ms: int
    end_ms: int
    gyro_t_ms: tuple[int, ...]
    gyro_xyz: tuple[tuple[float, float, float], ...]
    accel_t_ms: tuple[int, ...]
    accel_xyz: tuple[tuple[float, float, float], ...]


@dataclass(frozen=True)
class Description:
    stroke_type: str
    experience: str
    player: str
    peak_rad_s: float
    peak_offset_ms: int
    rise_ms: float | None
    prior_peak_ratio: float | None
    median_interval_ms: float
    max_interval_ms: int
    gaps_over_limit: int
    gyro_held_values: int
    gyro_samples: int
    gyro_saturated: bool
    accel_saturated: bool


@dataclass(frozen=True)
class Section:
    """Valid strokes of one section file plus the count of published invalid placeholders."""
    strokes: tuple[Stroke, ...]
    placeholders: int

    def __iter__(self):
        return iter(self.strokes)

    def __len__(self) -> int:
        return len(self.strokes)

    def __getitem__(self, index: int) -> Stroke:
        return self.strokes[index]


@dataclass(frozen=True)
class Source:
    name: str
    kind: str
    sha256: str | None
    section_files: int
    strokes: tuple[Stroke, ...]
    placeholders: int


# ---------------------------------------------------------------- parsing

def _require(mapping: object, keys: tuple[str, ...], where: str) -> dict:
    if not isinstance(mapping, dict):
        raise StrokeFormatError(f"{where} is not an object")
    for key in keys:
        if key not in mapping:
            raise StrokeFormatError(f"{where} missing key {key}")
    return mapping


def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _parse_stream(data: dict, name: str) -> tuple[tuple[int, ...], tuple[tuple[float, float, float], ...]]:
    if name not in data:
        raise StrokeFormatError(f"missing stream {name}")
    axes = STREAMS[name]
    stream = _require(data[name], (*axes, "timestamp"), name)
    unknown = sorted(set(stream) - {*axes, "timestamp"})
    if unknown:
        raise StrokeFormatError(f"{name} unknown key {unknown[0]}")
    columns = [stream[a] for a in axes]
    times = stream["timestamp"]
    if not all(isinstance(c, list) for c in (*columns, times)) or len({len(c) for c in (*columns, times)}) != 1:
        raise StrokeFormatError(f"{name} length mismatch")
    if len(times) < 2:
        raise StrokeFormatError(f"{name} has fewer than 2 samples")
    if not all(isinstance(t, int) and not isinstance(t, bool) for t in times):
        raise StrokeFormatError(f"{name} timestamp not an integer")
    if any(b <= a for a, b in zip(times, times[1:])):
        raise StrokeFormatError(f"{name} timestamps not strictly increasing")
    if not all(_is_number(v) for c in columns for v in c):
        raise StrokeFormatError(f"{name} value not a finite number")
    return tuple(times), tuple(zip(*(map(float, c) for c in columns)))


def _parse_stroke(raw: object) -> Stroke:
    entry = _require(raw, ("info", "label", "data"), "stroke")
    info = _require(entry["info"], INFO_KEYS, "info")
    label = _require(entry["label"], ("actionType",), "label")
    match = RECORD_NAME.match(str(info["recordName"]))
    if not match:
        raise StrokeFormatError(f"unexpected recordName {info['recordName']!r}")
    if match.group(3) != label["actionType"]:
        raise StrokeFormatError("recordName stroke type differs from actionType")
    start, end = info["startTimestamp"], info["endTimestamp"]
    if not (isinstance(start, int) and isinstance(end, int) and end > start):
        raise StrokeFormatError("info start/end timestamps malformed")
    if not isinstance(entry["data"], dict):
        raise StrokeFormatError("data is not an object")
    gyro_t, gyro = _parse_stream(entry["data"], "GYROSCOPE")
    accel_t, accel = _parse_stream(entry["data"], "ACCELEROMETER")
    return Stroke(info["recordName"], label["actionType"], str(info["exp"]), match.group(4), int(info["section"]),
                  str(info["device"]), start, end, gyro_t, gyro, accel_t, accel)


def _check_units(strokes: list[Stroke], where: str) -> None:
    gyro_max = max(_norm(v) for s in strokes for v in s.gyro_xyz)
    if gyro_max > PARAMETERS["max_plausible_gyro_rad_s"]:
        raise UnitsError(f"{where}: gyroscope values implausible for rad/s (max |w| {gyro_max:.1f})")
    low, high = PARAMETERS["plausible_median_accel_m_s2"]
    accel_median = _quantile([_norm(v) for s in strokes for v in s.accel_xyz], 0.5)
    if not low <= accel_median <= high:
        raise UnitsError(f"{where}: accelerometer values implausible for m/s^2 (median |a| {accel_median:.2f})")


def _is_placeholder(raw: object) -> bool:
    """Invalid attempts are published with info kept and both label and data null (113 of 961 in v1.0)."""
    return isinstance(raw, dict) and "info" in raw and raw.get("label", 0) is None and raw.get("data", 0) is None


def read_section(content: bytes, where: str) -> Section:
    try:
        entries = json.loads(content)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise StrokeFormatError(f"{where}: not valid JSON ({error})") from error
    if not isinstance(entries, list) or not entries:
        raise StrokeFormatError(f"{where}: expected a non-empty list of strokes")
    strokes, placeholders = [], 0
    for index, raw in enumerate(entries):
        if _is_placeholder(raw):
            placeholders += 1
            continue
        try:
            strokes.append(_parse_stroke(raw))
        except StrokeFormatError as error:
            raise StrokeFormatError(f"{where} stroke {index}: {error}") from error
    if not strokes:
        raise StrokeFormatError(f"{where}: no valid strokes")
    _check_units(strokes, where)
    return Section(tuple(strokes), placeholders)


def _sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def load_source(path: pathlib.Path) -> Source:
    """Read every section JSON from a .zip, a folder or one .json; never writes to the source."""
    strokes: list[Stroke] = []
    placeholders = 0
    if path.is_file() and path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as archive:
            names = sorted(n for n in archive.namelist()
                           if n.lower().endswith(".json") and not n.startswith("__MACOSX/"))
            for name in names:
                section = read_section(archive.read(name), name)
                strokes += section.strokes
                placeholders += section.placeholders
        return Source(path.name, "zip", _sha256(path), len(names), tuple(strokes), placeholders)
    files = [path] if path.is_file() else sorted(path.rglob("*.json"))
    if not files:
        raise StrokeFormatError(f"{path.name}: no section .json files found")
    for file in files:
        section = read_section(file.read_bytes(), file.name if file == path else file.relative_to(path).as_posix())
        strokes += section.strokes
        placeholders += section.placeholders
    kind = "file" if path.is_file() else "directory"
    return Source(path.name, kind, None, len(files), tuple(strokes), placeholders)


# ---------------------------------------------------------------- description

def _norm(v: tuple[float, float, float]) -> float:
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def _quantile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * q
    low, high = math.floor(position), math.ceil(position)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def _rise(speed: list[float], times: tuple[int, ...], peak: int) -> tuple[float | None, float | None]:
    """Rise time from the last upward crossing of a fraction of the peak, and the prior-peak ratio.

    The prior peak is the largest speed before the valley (last minimum) that precedes the rise, so
    the approach to the rise threshold itself never counts as an earlier peak.
    """
    threshold = PARAMETERS["rise_fraction_of_peak"] * speed[peak]
    below = [i for i in range(peak) if speed[i] < threshold]
    if not below:
        return None, None
    i = below[-1]
    crossing = times[i] + (threshold - speed[i]) / (speed[i + 1] - speed[i]) * (times[i + 1] - times[i])
    lowest = min(speed[: i + 1])
    valley = max(j for j in range(i + 1) if speed[j] == lowest)
    return times[peak] - crossing, max(speed[: valley + 1]) / speed[peak]


def describe(stroke: Stroke) -> Description:
    speed = [_norm(v) for v in stroke.gyro_xyz]
    peak = max(range(len(speed)), key=speed.__getitem__)
    rise_ms, prior = _rise(speed, stroke.gyro_t_ms, peak)
    intervals = [b - a for a, b in zip(stroke.gyro_t_ms, stroke.gyro_t_ms[1:])]
    gyro_clip, accel_clip = PARAMETERS["gyro_saturation_rad_s"], PARAMETERS["accel_saturation_m_s2"]
    return Description(
        stroke_type=stroke.stroke_type, experience=stroke.experience, player=stroke.player,
        peak_rad_s=speed[peak], peak_offset_ms=stroke.gyro_t_ms[peak] - stroke.start_ms,
        rise_ms=rise_ms, prior_peak_ratio=prior,
        median_interval_ms=_quantile(intervals, 0.5), max_interval_ms=max(intervals),
        gaps_over_limit=sum(1 for d in intervals if d > PARAMETERS["gap_limit_ms"]),
        gyro_held_values=sum(1 for a, b in zip(stroke.gyro_xyz, stroke.gyro_xyz[1:]) if a == b),
        gyro_samples=len(speed),
        gyro_saturated=any(abs(x) >= gyro_clip for v in stroke.gyro_xyz for x in v),
        accel_saturated=any(abs(x) >= accel_clip for v in stroke.accel_xyz for x in v),
    )


# ---------------------------------------------------------------- report

def _spread(values: list[float]) -> dict | None:
    if not values:
        return None
    return {k: round(_quantile(values, q), 2) for k, q in (("p10", 0.1), ("median", 0.5), ("p90", 0.9))}


def _summary(group: list[Description]) -> dict:
    n = len(group)
    priors = [d.prior_peak_ratio for d in group if d.prior_peak_ratio is not None]
    share = PARAMETERS["prior_peak_share_threshold"]
    return {
        "strokes": n,
        "peak_rad_s": _spread([d.peak_rad_s for d in group]),
        "peak_gyro_saturated_share": round(sum(d.gyro_saturated for d in group) / n, 3),
        "rise_ms": _spread([d.rise_ms for d in group if d.rise_ms is not None]),
        "prior_peak_ratio": _spread(priors),
        "prior_peak_over_threshold_share": round(sum(p >= share for p in priors) / len(priors), 3) if priors else None,
        "pre_peak_history_ms": _spread([float(d.peak_offset_ms) for d in group]),
    }


def build_report(source: Source, descriptions: list[Description]) -> dict:
    groups: dict[str, dict[str, list[Description]]] = {"stroke_type": defaultdict(list),
                                                        "experience": defaultdict(list), "player": defaultdict(list)}
    for d in descriptions:
        groups["stroke_type"][d.stroke_type].append(d)
        groups["experience"][d.experience].append(d)
        groups["player"][d.player].append(d)
    samples = sum(d.gyro_samples for d in descriptions)
    return {
        "category": "external/off-domain",
        "title": "EXTERNAL / OFF-DOMAIN - BADS_CLL descriptive stroke report",
        "source": {"dataset": DATASET, "dataset_version": DATASET_VERSION, "license": "CC BY-NC-ND 4.0",
                   "citation": CITATION, "input": source.name, "input_kind": source.kind, "sha256": source.sha256,
                   "expected_sha256": EXPECTED_SHA256,
                   "sha256_matches": None if source.sha256 is None else source.sha256 == EXPECTED_SHA256,
                   "section_files": source.section_files},
        "adapter": {"name": "external-stroke-reader", "version": ADAPTER_VERSION},
        "units": UNITS,
        "parameters": PARAMETERS,
        "totals": {
            "strokes": len(descriptions),
            "invalid_placeholders": source.placeholders,
            "gyro_saturated_strokes": sum(d.gyro_saturated for d in descriptions),
            "accel_saturated_strokes": sum(d.accel_saturated for d in descriptions),
            "strokes_with_gap_over_limit": sum(d.gaps_over_limit > 0 for d in descriptions),
            "median_interval_ms": _spread([d.median_interval_ms for d in descriptions]),
            "max_interval_ms": max(d.max_interval_ms for d in descriptions),
            "held_gyro_sample_share": round(sum(d.gyro_held_values for d in descriptions) / samples, 4),
            "overall": _summary(descriptions),
        },
        "groups": {name: {key: _summary(items) for key, items in sorted(by.items())} for name, by in groups.items()},
        "limitations": LIMITATIONS,
    }


def _fmt(spread: dict | None) -> str:
    return "-" if spread is None else f"{spread['median']} ({spread['p10']}-{spread['p90']})"


def render_markdown(report: dict) -> str:
    src, totals = report["source"], report["totals"]
    lines = [
        "# EXTERNAL / OFF-DOMAIN - BADS_CLL descriptive stroke report", "",
        "> Category `external/off-domain`. Not TMB-030 tune or held-out data and not detector or product evidence.",
        "", f"- Dataset: {src['dataset']} {src['dataset_version']}, {src['license']}",
        f"- Citation: {src['citation']}",
        f"- Input: `{src['input']}` ({src['input_kind']}, {src['section_files']} section files); "
        f"SHA-256 {src['sha256'] or 'not computed for non-archive input'}"
        + ("" if src["sha256_matches"] is None else f" (matches recorded: {src['sha256_matches']})"),
        f"- Adapter: {report['adapter']['name']} v{report['adapter']['version']}; units: "
        + ", ".join(f"{k} {v}" for k, v in report["units"].items()),
        f"- Parameters: `{json.dumps(report['parameters'])}`", "",
        "## Totals", "",
        f"- Strokes: {totals['strokes']} (published invalid placeholders skipped: "
        f"{totals['invalid_placeholders']}); gyro-saturated: {totals['gyro_saturated_strokes']}; "
        f"accel-saturated: {totals['accel_saturated_strokes']}; with a gap over "
        f"{report['parameters']['gap_limit_ms']} ms: {totals['strokes_with_gap_over_limit']}",
        f"- Median interval ms: {_fmt(totals['median_interval_ms'])}; max interval {totals['max_interval_ms']} ms; "
        f"held gyro samples {totals['held_gyro_sample_share']:.2%}", "",
        "Values are median (p10-p90).", "",
    ]
    header = ("| Group | Strokes | Peak rad/s | Peak saturated | Rise ms | Prior-peak ratio | Prior >= "
              f"{report['parameters']['prior_peak_share_threshold']} | Pre-peak ms |")
    for name, groups in [("overall", {"all": totals["overall"]}), *report["groups"].items()]:
        lines += [f"## By {name}" if name != "overall" else "## Overall", "", header, "|---" * 8 + "|"]
        for key, s in groups.items():
            share = "-" if s["prior_peak_over_threshold_share"] is None else f"{s['prior_peak_over_threshold_share']:.0%}"
            lines.append(f"| {key} | {s['strokes']} | {_fmt(s['peak_rad_s'])} | {s['peak_gyro_saturated_share']:.0%} | "
                         f"{_fmt(s['rise_ms'])} | {_fmt(s['prior_peak_ratio'])} | {share} | "
                         f"{_fmt(s['pre_peak_history_ms'])} |")
        lines.append("")
    lines += ["## Limitations", "", *(f"- {item}" for item in report["limitations"]), ""]
    return "\n".join(lines)


# ---------------------------------------------------------------- CLI

def output_allowed(path: pathlib.Path) -> bool:
    """Reports are derived material: only outside the public repo or in git-ignored external-data/."""
    resolved = path.resolve()
    if not resolved.is_relative_to(REPO_ROOT):
        return True
    return resolved.is_relative_to(ALLOWED_IN_REPO)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=pathlib.Path, help="archive .zip, extracted folder or one section .json")
    parser.add_argument("--json", type=pathlib.Path)
    parser.add_argument("--markdown", type=pathlib.Path)
    args = parser.parse_args(argv)
    for target in (args.json, args.markdown):
        if target is not None and not output_allowed(target):
            print(f"refusing to write {target}: reports are derived from CC BY-NC-ND data and this is a public "
                  "repository; write outside it or under external-data/", file=sys.stderr)
            return 2
    try:
        source = load_source(args.source)
    except (StrokeFormatError, UnitsError, zipfile.BadZipFile, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    report = build_report(source, [describe(s) for s in source.strokes])
    for target, text in ((args.json, json.dumps(report, indent=2) + "\n"), (args.markdown, render_markdown(report))):
        if target is not None:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")
    totals = report["totals"]
    print(f"external/off-domain: {totals['strokes']} strokes from {source.section_files} section files; "
          f"gyro-saturated {totals['gyro_saturated_strokes']}, accel-saturated {totals['accel_saturated_strokes']}; "
          f"sha256 match: {report['source']['sha256_matches']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
