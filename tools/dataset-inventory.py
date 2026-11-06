#!/usr/bin/env python3
"""TMB-030 dataset inventory and coverage report for labeled captures.

Scans a captures root (docs/capture-format.md), verifies every raw.sha256,
applies the session split in dataset-splits.json and reports, per phone,
valid swings and non-swing minutes by shot, speed, hand, player and split,
plus excluded takes, coverage gaps against the ticket minimums, a checksum
list and fields that need a privacy review.

  dataset-inventory.py CAPTURES_ROOT [--json out.json] [--markdown out.md]
                       [--min-swings 100] [--min-nonswing-minutes 20]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
from collections import Counter
from dataclasses import dataclass, field

SWING_SHOTS = {"smash", "clear", "drop", "lift", "other_swing"}
NONSWING_SHOTS = {"idle", "handling", "walking"}
SPLITS = ("tune", "heldout")
EXCLUDE = "exclude"  # kept on disk and checksummed, but not part of the dataset
TAKE_FIELDS = {"record", "take_id", "revision", "player", "phone", "handedness", "intended_shot", "valid",
               "speed", "swing_count", "start_arrival_ns", "end_arrival_ns"}
METADATA_FIELDS = {"source", "purpose"}
NS_PER_MINUTE = 60_000_000_000


class InventoryError(ValueError):
    """Unusable input (bad split file)."""


@dataclass
class PhoneTotals:
    swings: int = 0
    swings_by_shot: Counter = field(default_factory=Counter)
    swings_by_speed: Counter = field(default_factory=Counter)
    swings_by_hand: Counter = field(default_factory=Counter)
    swings_by_player: Counter = field(default_factory=Counter)
    swings_by_split: Counter = field(default_factory=Counter)
    nonswing_minutes: float = 0.0
    nonswing_minutes_by_type: Counter = field(default_factory=Counter)
    nonswing_minutes_by_split: Counter = field(default_factory=Counter)
    excluded_takes: int = 0
    excluded_swings: int = 0

    def as_dict(self) -> dict:
        def sort(counter: Counter) -> dict:
            return {key: (round(value, 2) if isinstance(value, float) else value)
                    for key, value in sorted(counter.items())}
        return {
            "swings": self.swings,
            "swings_by_shot": sort(self.swings_by_shot),
            "swings_by_speed": sort(self.swings_by_speed),
            "swings_by_hand": sort(self.swings_by_hand),
            "swings_by_player": sort(Counter({str(k): v for k, v in self.swings_by_player.items()})),
            "swings_by_split": sort(self.swings_by_split),
            "nonswing_minutes": round(self.nonswing_minutes, 2),
            "nonswing_minutes_by_type": sort(self.nonswing_minutes_by_type),
            "nonswing_minutes_by_split": sort(self.nonswing_minutes_by_split),
            "excluded_takes": self.excluded_takes,
            "excluded_swings": self.excluded_swings,
        }


def read_splits(root: pathlib.Path) -> dict[str, str]:
    path = root / "dataset-splits.json"
    if not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    sessions = data.get("sessions", {}) if isinstance(data, dict) else {}
    for capture_id, split in sessions.items():
        if split not in (*SPLITS, EXCLUDE):
            raise InventoryError(f"{capture_id}: split must be tune or heldout (or exclude), got {split!r}")
    return dict(sessions)


def effective_takes(capture: pathlib.Path) -> list[dict]:
    latest: dict[int, dict] = {}
    for line in (capture / "labels.jsonl").read_text(encoding="utf-8").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict) and record.get("record") == "take":
            take_id = int(record.get("take_id", 0))
            if take_id not in latest or int(record.get("revision", 0)) >= int(latest[take_id].get("revision", 0)):
                latest[take_id] = record
    return [latest[key] for key in sorted(latest)]


def checksum(capture: pathlib.Path) -> tuple[bool, str]:
    raw = capture / "raw.jsonl"
    actual = hashlib.sha256(raw.read_bytes()).hexdigest()
    sidecar = capture / "raw.sha256"
    expected = sidecar.read_text(encoding="utf-8").split()[0] if sidecar.is_file() else ""
    return expected == actual, actual


def header_metadata(capture: pathlib.Path) -> dict:
    with (capture / "raw.jsonl").open(encoding="utf-8") as handle:
        first = handle.readline()
    try:
        header = json.loads(first)
    except json.JSONDecodeError:
        return {}
    return header.get("metadata", {}) if isinstance(header, dict) else {}


def inventory(root: pathlib.Path, min_swings: int, min_nonswing_minutes: float) -> dict:
    splits = read_splits(root)
    phones: dict[str, PhoneTotals] = {}
    heldout_swing: Counter = Counter()
    heldout_nonswing: Counter = Counter()
    players: set[int] = set()
    captures, gaps, privacy = [], [], []
    for directory in sorted(p for p in root.iterdir() if (p / "labels.jsonl").is_file() and (p / "raw.jsonl").is_file()):
        capture_id = directory.name
        split = splits.get(capture_id, "unassigned")
        verified, digest = checksum(directory)
        captures.append({"capture_id": capture_id, "split": split, "raw_sha256": digest, "raw_verified": verified})
        if not verified:
            gaps.append(f"{capture_id} raw checksum mismatch or missing raw.sha256")
        if split == EXCLUDE:
            continue
        if split == "unassigned":
            gaps.append(f"{capture_id} is not assigned to tune or heldout in dataset-splits.json")
        for key in sorted(set(header_metadata(directory)) - METADATA_FIELDS):
            privacy.append(f"{capture_id} metadata field {key}")
        for take in effective_takes(directory):
            for key in sorted(set(take) - TAKE_FIELDS):
                privacy.append(f"{capture_id} take {take.get('take_id')} field {key}")
            totals = phones.setdefault(str(take.get("phone", "unknown")), PhoneTotals())
            shot = str(take.get("intended_shot", ""))
            swings = int(take.get("swing_count", 0))
            if not bool(take.get("valid", False)):
                totals.excluded_takes += 1
                totals.excluded_swings += swings if shot in SWING_SHOTS else 0
                continue
            players.add(int(take.get("player", 0)))
            if shot in SWING_SHOTS:
                totals.swings += swings
                totals.swings_by_shot[shot] += swings
                totals.swings_by_speed[str(take.get("speed", "none"))] += swings
                totals.swings_by_hand[str(take.get("handedness", ""))] += swings
                totals.swings_by_player[int(take.get("player", 0))] += swings
                totals.swings_by_split[split] += swings
                if split == "heldout" and swings > 0:
                    heldout_swing[str(take.get("phone"))] += 1
            elif shot in NONSWING_SHOTS:
                minutes = max(0, int(take["end_arrival_ns"]) - int(take["start_arrival_ns"])) / NS_PER_MINUTE
                totals.nonswing_minutes += minutes
                totals.nonswing_minutes_by_type[shot] += minutes
                totals.nonswing_minutes_by_split[split] += minutes
                if split == "heldout":
                    heldout_nonswing[str(take.get("phone"))] += 1
    for phone, totals in sorted(phones.items()):
        if totals.swings < min_swings:
            gaps.append(f"{phone}: {totals.swings} of {min_swings} swings")
        if totals.nonswing_minutes < min_nonswing_minutes:
            gaps.append(f"{phone}: {round(totals.nonswing_minutes, 2)} of {min_nonswing_minutes:g} non-swing minutes")
        if heldout_swing[phone] == 0:
            gaps.append(f"{phone}: no held-out swing session")
        if heldout_nonswing[phone] == 0:
            gaps.append(f"{phone}: no held-out non-swing session")
        if len(totals.swings_by_hand) < 2:
            gaps.append(f"{phone}: swings from one hand only ({', '.join(totals.swings_by_hand) or 'none'})")
    if len(players) < 2:
        gaps.append(f"Dataset has only player {', '.join(map(str, sorted(players))) or 'none'} "
                    "(second intended player missing)")
    return {
        "inventory_format": 1,
        "minimums": {"swings_per_phone": min_swings, "nonswing_minutes_per_phone": min_nonswing_minutes},
        "phones": {phone: totals.as_dict() for phone, totals in sorted(phones.items())},
        "captures": captures,
        "gaps": gaps,
        "privacy_review": privacy,
        "meets_minimums": not gaps,
    }


def markdown(report: dict) -> str:
    lines = ["# TMB-030 dataset inventory", ""]
    minimums = report["minimums"]
    lines.append(f"Minimums per phone: {minimums['swings_per_phone']} swings, "
                 f"{minimums['nonswing_minutes_per_phone']:g} non-swing minutes.")
    lines += ["", "| Phone | Swings | Tune / held-out swings | Non-swing min | Excluded takes |",
              "| --- | ---: | --- | ---: | ---: |"]
    for phone, totals in report["phones"].items():
        split = totals["swings_by_split"]
        lines.append(f"| {phone} | {totals['swings']} | {split.get('tune', 0)} / {split.get('heldout', 0)} | "
                     f"{totals['nonswing_minutes']} | {totals['excluded_takes']} |")
    for phone, totals in report["phones"].items():
        lines += ["", f"## {phone}", "",
                  f"- Swings by shot: {totals['swings_by_shot']}",
                  f"- Swings by speed: {totals['swings_by_speed']}",
                  f"- Swings by hand: {totals['swings_by_hand']}",
                  f"- Non-swing minutes by type: {totals['nonswing_minutes_by_type']}",
                  f"- Non-swing minutes by split: {totals['nonswing_minutes_by_split']}"]
    lines += ["", "## Coverage gaps", ""] + ([f"- {gap}" for gap in report["gaps"]] or ["- None"])
    lines += ["", "## Privacy review", ""] + ([f"- {item}" for item in report["privacy_review"]] or ["- None"])
    lines += ["", "## Raw capture checksums (SHA-256)", "", "| Capture | Split | Verified | SHA-256 |",
              "| --- | --- | --- | --- |"]
    for item in report["captures"]:
        lines.append(f"| {item['capture_id']} | {item['split']} | {'yes' if item['raw_verified'] else 'NO'} | "
                     f"`{item['raw_sha256']}` |")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", type=pathlib.Path)
    parser.add_argument("--json", type=pathlib.Path)
    parser.add_argument("--markdown", type=pathlib.Path)
    parser.add_argument("--min-swings", type=int, default=100)
    parser.add_argument("--min-nonswing-minutes", type=float, default=20.0)
    args = parser.parse_args(argv)
    if not args.root.is_dir():
        print(f"Captures root not found: {args.root}", file=sys.stderr)
        return 2
    try:
        report = inventory(args.root, args.min_swings, args.min_nonswing_minutes)
    except (InventoryError, json.JSONDecodeError) as error:
        print(f"Invalid dataset-splits.json: {error}", file=sys.stderr)
        return 2
    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    text = markdown(report)
    if args.markdown:
        args.markdown.write_text(text, encoding="utf-8")
    print(f"TMB-030_INVENTORY phones={len(report['phones'])} captures={len(report['captures'])} "
          f"gaps={len(report['gaps'])} meets_minimums={str(report['meets_minimums']).lower()}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
