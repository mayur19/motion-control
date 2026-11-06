#!/usr/bin/env python3
"""Plot raw vs normalized motion axes from a host session log (TMB-028).

Reads `normalized_sample` records (host flag --log-normalized-motion) and
writes one PNG with, per controller, raw device-frame axes beside the same
samples in the common racket frame (acceleration and angular velocity).

Usage: plot-normalization.py SESSION.jsonl --output plot.png [--controller ID]
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from dataclasses import dataclass

AXES = ("x", "y", "z")
SIGNALS = (("acceleration", "m/s²"), ("angular_velocity", "rad/s"))


@dataclass(frozen=True)
class Sample:
    controller_id: int
    time_s: float
    raw: dict[str, tuple[float, float, float]]
    normalized: dict[str, tuple[float, float, float]]


def read_samples(path: pathlib.Path, controller: int | None) -> list[Sample]:
    samples: list[Sample] = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue  # a killed host truncates the last line
            if not isinstance(record, dict) or record.get("record_type") != "normalized_sample":
                continue
            cid = int(record.get("controller_id", 0))
            if controller is not None and cid != controller:
                continue
            try:
                samples.append(Sample(
                    controller_id=cid,
                    time_s=int(record["sensor_monotonic_ns"]) / 1e9,
                    raw={name: _vector(record[f"raw_{name}"]) for name, _ in SIGNALS},
                    normalized={name: _vector(record[f"normalized_{name}"]) for name, _ in SIGNALS},
                ))
            except (KeyError, TypeError, ValueError):
                continue
    return samples


def _vector(values: object) -> tuple[float, float, float]:
    if not isinstance(values, list) or len(values) != 3:
        raise ValueError("expected a 3-vector")
    return (float(values[0]), float(values[1]), float(values[2]))


def plot(samples: list[Sample], output: pathlib.Path) -> int:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    controllers = sorted({s.controller_id for s in samples})
    rows = len(controllers) * len(SIGNALS)
    figure, axes = plt.subplots(rows, 2, figsize=(13, 2.6 * rows), squeeze=False, sharex="row")
    for c_index, cid in enumerate(controllers):
        series = [s for s in samples if s.controller_id == cid]
        start = series[0].time_s
        times = [s.time_s - start for s in series]
        for s_index, (name, unit) in enumerate(SIGNALS):
            row = c_index * len(SIGNALS) + s_index
            for column, (frame, label) in enumerate((("raw", "raw device frame"),
                                                     ("normalized", "normalized racket frame"))):
                ax = axes[row][column]
                for a_index, axis in enumerate(AXES):
                    ax.plot(times, [getattr(s, frame)[name][a_index] for s in series], label=axis,
                            linewidth=1.0)
                ax.set_title(f"controller {cid:x} — {name} ({unit}), {label}", fontsize=9)
                ax.grid(alpha=0.3)
                ax.legend(loc="upper right", fontsize=7)
            axes[row][0].set_ylabel(unit)
    for ax in axes[-1]:
        ax.set_xlabel("sensor time since first sample (s)")
    figure.tight_layout()
    figure.savefig(output, dpi=110)
    plt.close(figure)
    return len(controllers)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--controller", type=lambda v: int(v, 0), default=None,
                        help="controller id (decimal or 0x hex)")
    args = parser.parse_args(argv)
    if not args.log.is_file():
        print(f"Log not found: {args.log}", file=sys.stderr)
        return 2
    samples = read_samples(args.log, args.controller)
    if not samples:
        print("No normalized_sample records; run the host with --log-normalized-motion "
              "and calibrate a controller.", file=sys.stderr)
        return 2
    controllers = plot(samples, args.output)
    print(f"TMB-028_PLOT_OK controllers={controllers} samples={len(samples)} output={args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
