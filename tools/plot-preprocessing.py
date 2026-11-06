#!/usr/bin/env python3
"""Plot normalized vs preprocessed motion from a replay series (TMB-031).

Input: the JSONL written by replay_capture.gd --series=FILE. Output: one PNG
per run with, per controller, angular speed and acceleration magnitude before
and after preprocessing, plus a printed summary of how much the filter
changed the signal.

Usage: plot-preprocessing.py SERIES.jsonl --output plot.png [--start S --end S]
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys


def read(path: pathlib.Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(row, dict) and "preprocessed_angular_speed" in row:
                rows.append(row)
    return rows


def magnitude(values: list) -> float:
    return math.sqrt(sum(float(v) ** 2 for v in values))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("series", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--start", type=float, default=None, help="seconds from first sample")
    parser.add_argument("--end", type=float, default=None, help="seconds from first sample")
    args = parser.parse_args(argv)
    rows = read(args.series) if args.series.is_file() else []
    if not rows:
        print("No samples in series; run replay_capture.gd with --series.", file=sys.stderr)
        return 2
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    controllers = sorted({int(r["controller_id"]) for r in rows})
    figure, axes = plt.subplots(len(controllers) * 2, 1, figsize=(13, 3.2 * 2 * len(controllers)), squeeze=False)
    changes = []
    for index, cid in enumerate(controllers):
        series = [r for r in rows if int(r["controller_id"]) == cid]
        t0 = int(series[0]["sensor_monotonic_ns"])
        times = [(int(r["sensor_monotonic_ns"]) - t0) / 1e9 for r in series]
        keep = [i for i, t in enumerate(times)
                if (args.start is None or t >= args.start) and (args.end is None or t <= args.end)]
        t = [times[i] for i in keep]
        before = [float(series[i]["normalized_angular_speed"]) for i in keep]
        after = [float(series[i]["preprocessed_angular_speed"]) for i in keep]
        accel_before = [magnitude(series[i]["normalized_acceleration"]) for i in keep]
        accel_after = [magnitude(series[i]["preprocessed_acceleration"]) for i in keep]
        changes += [(b - a) ** 2 for b, a in zip(before, after)]
        for row, (label, unit, raw, filtered) in enumerate((
                ("angular speed", "rad/s", before, after),
                ("acceleration magnitude", "m/s²", accel_before, accel_after))):
            ax = axes[index * 2 + row][0]
            ax.plot(t, raw, label="normalized (before)", linewidth=0.8, alpha=0.6)
            ax.plot(t, filtered, label="preprocessed (after)", linewidth=1.2)
            ax.set_title(f"controller {cid:x} — {label}", fontsize=9)
            ax.set_ylabel(unit)
            ax.grid(alpha=0.3)
            ax.legend(loc="upper right", fontsize=7)
    axes[-1][0].set_xlabel("sensor time since first sample (s)")
    figure.tight_layout()
    figure.savefig(args.output, dpi=110)
    plt.close(figure)
    rms = math.sqrt(sum(changes) / len(changes)) if changes else 0.0
    resets = sum(1 for r in rows if r.get("gap_reset"))
    print(f"TMB-031_PLOT_OK controllers={len(controllers)} samples={len(rows)} "
          f"rms_change_rad_s={rms:.4f} gap_resets={resets} output={args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
