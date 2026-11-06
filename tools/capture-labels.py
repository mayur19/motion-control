#!/usr/bin/env python3
"""List, correct and verify TMB-029 capture labels (docs/capture-format.md).

Raw motion (raw.jsonl) is never modified. A correction appends a new
revision of the take to labels.jsonl; the latest revision is effective.

  capture-labels.py list    CAPTURE_DIR
  capture-labels.py correct CAPTURE_DIR --take N --set field=value [--set ...]
  capture-labels.py verify  CAPTURE_DIR
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys

SHOTS = ("smash", "clear", "drop", "lift", "other_swing", "idle", "handling", "walking")
PHONE = re.compile(r"^[A-Za-z0-9 _-]{1,32}$")
EDITABLE = ("player", "phone", "handedness", "intended_shot", "valid")


class LabelError(ValueError):
    """Invalid label correction."""


def read_takes(capture: pathlib.Path) -> dict[int, dict]:
    latest: dict[int, dict] = {}
    for line in (capture / "labels.jsonl").read_text(encoding="utf-8").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(record, dict) or record.get("record") != "take":
            continue
        take_id = int(record["take_id"])
        if take_id not in latest or int(record.get("revision", 0)) >= int(latest[take_id].get("revision", 0)):
            latest[take_id] = record
    return dict(sorted(latest.items()))


def parse_value(field: str, value: str) -> object:
    if field not in EDITABLE:
        raise LabelError(f"{field} is not an editable label (allowed: {', '.join(EDITABLE)})")
    if field == "player":
        if value not in ("1", "2"):
            raise LabelError("player must be 1 or 2")
        return int(value)
    if field == "phone":
        if not PHONE.match(value):
            raise LabelError("phone must be a short label (letters, digits, space, _ or -)")
        return value
    if field == "handedness":
        if value not in ("right", "left"):
            raise LabelError("handedness must be right or left")
        return value
    if field == "intended_shot":
        if value not in SHOTS:
            raise LabelError(f"intended_shot must be one of {', '.join(SHOTS)}")
        return value
    if value not in ("true", "false"):
        raise LabelError("valid must be true or false")
    return value == "true"


def corrected_take(current: dict, assignments: list[str]) -> dict:
    changes: dict[str, object] = {}
    for assignment in assignments:
        field, separator, value = assignment.partition("=")
        if not separator:
            raise LabelError(f"expected field=value, got {assignment!r}")
        changes[field] = parse_value(field, value)
    return {**current, **changes, "revision": int(current.get("revision", 0)) + 1}


def verify(capture: pathlib.Path) -> tuple[bool, str]:
    checksum = capture / "raw.sha256"
    raw = capture / "raw.jsonl"
    if not checksum.is_file() or not raw.is_file():
        return False, "missing raw.jsonl or raw.sha256"
    expected = checksum.read_text(encoding="utf-8").split()[0]
    actual = hashlib.sha256(raw.read_bytes()).hexdigest()
    return expected == actual, ("ok" if expected == actual else "mismatch") + f" sha256={actual}"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("list", "verify"):
        sub.add_parser(name).add_argument("capture", type=pathlib.Path)
    correct = sub.add_parser("correct")
    correct.add_argument("capture", type=pathlib.Path)
    correct.add_argument("--take", type=int, required=True)
    correct.add_argument("--set", action="append", required=True, metavar="FIELD=VALUE")
    args = parser.parse_args(argv)

    if not (args.capture / "labels.jsonl").is_file():
        print(f"Not a capture directory: {args.capture}", file=sys.stderr)
        return 2
    if args.command == "verify":
        ok, message = verify(args.capture)
        print(message)
        return 0 if ok else 1
    takes = read_takes(args.capture)
    if args.command == "list":
        for take_id, take in takes.items():
            print(f"take {take_id} rev {take.get('revision')}: P{take.get('player')} {take.get('phone')} "
                  f"{take.get('handedness')} {take.get('intended_shot')} "
                  f"{'valid' if take.get('valid') else 'INVALID'}")
        return 0
    if args.take not in takes:
        print(f"No take {args.take} in {args.capture}", file=sys.stderr)
        return 2
    try:
        record = corrected_take(takes[args.take], args.set)
    except LabelError as error:
        print(f"Rejected: {error}", file=sys.stderr)
        return 2
    labels = args.capture / "labels.jsonl"
    torn = labels.stat().st_size > 0 and not labels.read_bytes().endswith(b"\n")
    with labels.open("a", encoding="utf-8") as handle:
        handle.write(("\n" if torn else "") + json.dumps(record) + "\n")
    print(f"take {args.take} rev {record['revision']} written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
