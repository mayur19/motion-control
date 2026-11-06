#!/usr/bin/env python3
"""Summarise a host session JSONL soak window against TMB-022 thresholds.

Usage: python3 -I tools/soak-report.py <session.jsonl> <start_host_s> [end_host_s]

Per controller: sensor/accepted rate, loss, duplicates, reorder, late samples
(age above the spec's 50 ms stale limit, per packet), jitter, RTT and state
changes. Host: frame time, static memory trend and queue drops. Output holds
controller IDs, players and metrics only; no addresses or secrets.
"""
import json
import statistics
import sys

MIN_MEDIAN_RATE_HZ = 99.0  # owner decision 2026-11-06: median >= 99 Hz per phone
MAX_FRAME_MS = 150.0       # owner decision: no frame over 150 ms
MAX_FRAME_P99_MS = 50.0    # owner decision: frame-time p99 under 50 ms
MAX_BAD_PERCENT = 1.0
STALE_LIMIT_MS = 50.0
FUTURE_LIMIT_MS = 20.0
NS_PER_MS = 1_000_000
NS_PER_S = 1_000_000_000
MOTION = 5


def load(path: str, start_ns: int, end_ns: int) -> dict:
    data = {"soak": {}, "states": [], "players": {}, "packets": {}, "offsets": {}}
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")[:-1]  # last element is "" or a truncated tail
    for line in lines:
        record = json.loads(line)
        t = record.get("host_monotonic_ns") or record.get("arrival_monotonic_ns") or 0
        event = record.get("event")
        if event == "pairing" and record.get("state") == 1:
            data["players"][record["controller_id"]] = record["player"]
        if event == "clock_sync":
            data["offsets"].setdefault(record["controller_id"], []).append((t, record["offset_ms"]))
        if not start_ns <= t <= end_ns:
            continue
        if event == "soak_metrics":
            data["soak"].setdefault(record["controller_id"], []).append(record)
        elif event == "controller_state":
            data["states"].append(record)
        elif record.get("record_type") == "packet" and record.get("message_type") == MOTION:
            data["packets"].setdefault(record["controller_id"], []).append(record)
    return data


def offset_at(offsets: list, t: int):
    current = None
    for when, value in offsets:
        if when > t:
            break
        current = value
    return current


def ages(packets: list, offsets: list) -> list:
    result = []
    for packet in packets:
        offset = offset_at(offsets, packet["arrival_monotonic_ns"])
        if offset is None or not packet["sensor_monotonic_ns"]:
            continue
        host_sample = packet["sensor_monotonic_ns"] - offset * NS_PER_MS
        result.append((packet["arrival_monotonic_ns"] - host_sample) / NS_PER_MS)
    return result


def pct(values: list, q: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(q * len(ordered)))] if ordered else 0.0


MIN_INTERVALS = 3


def measurable(cid: int, data: dict) -> bool:
    connected = [m for m in data["soak"].get(cid, []) if m["connection_state"] == "Connected"]
    return len(connected) >= MIN_INTERVALS


def controller_report(cid: int, data: dict) -> bool:
    soak = [m for m in data["soak"].get(cid, []) if m["connection_state"] == "Connected"]
    first, last = soak[0], soak[-1]
    rates = [m["received_motion_hz"] for m in soak[1:]]
    accepted = sum(m["received_motion_hz"] * m["interval_seconds"] for m in soak)
    loss = last["loss_packets"] - first["loss_packets"]
    dups = last["duplicate_packets"] - first["duplicate_packets"]
    reorder = last["reordered_packets"] - first["reordered_packets"]
    sample_ages = ages(data["packets"].get(cid, []), data["offsets"].get(cid, []))
    late = sum(1 for a in sample_ages if a > STALE_LIMIT_MS or a < -FUTURE_LIMIT_MS)
    total = accepted + loss
    bad_pct = 100.0 * (loss + late) / total if total else 100.0
    below = sum(1 for r in rates if r < MIN_MEDIAN_RATE_HZ)
    rate_ok = statistics.median(rates) >= MIN_MEDIAN_RATE_HZ
    bad_ok = bad_pct < MAX_BAD_PERCENT
    player = data["players"].get(cid, "?")
    print(f"\nP{player} controller {cid}: {len(soak)} Connected intervals")
    print(f"  sensor Hz       median {statistics.median(m['actual_sensor_hz'] for m in soak):.0f}")
    print(f"  accepted /s     median {statistics.median(rates):.1f}  min {min(rates):.1f}  "
          f"intervals <{MIN_MEDIAN_RATE_HZ:.0f}: {below}/{len(rates)}   "
          f"[{'PASS' if rate_ok else 'FAIL'} median >= {MIN_MEDIAN_RATE_HZ:.0f} Hz]")
    print(f"  packets         accepted ~{accepted:.0f}  loss {loss}  dup {dups}  reorder {reorder}")
    print(f"  late (>{STALE_LIMIT_MS:.0f} ms)  {late} of {len(sample_ages)} aged samples")
    print(f"  dropped+late    {bad_pct:.3f}%   [{'PASS' if bad_ok else 'FAIL'} < {MAX_BAD_PERCENT:.0f}%]")
    print(f"  sample age ms   median {statistics.median(sample_ages):.1f}  p95 {pct(sample_ages, .95):.1f}  "
          f"p99 {pct(sample_ages, .99):.1f}  max {max(sample_ages):.1f}")
    print(f"  jitter ms       median {statistics.median(m['network_jitter_ms'] for m in soak):.1f}  "
          f"max {max(m['network_jitter_ms'] for m in soak):.1f}")
    print(f"  clock RTT ms    median {statistics.median(m['clock_rtt_ms'] for m in soak):.1f}  "
          f"max {max(m['clock_rtt_ms'] for m in soak):.1f}")
    changes = [s for s in data["states"] if s["controller_id"] == cid]
    print(f"  state changes   {len(changes)}" + "".join(
        f"\n    {s['host_monotonic_ns'] / NS_PER_S:8.2f} {s['state']} ({s['reason']})" for s in changes))
    return rate_ok and bad_ok


def frame_p99_verdict(frames: list) -> tuple:
    """Returns (p99_ms_or_None, passes, explanation). Uses logged per-second p99
    when present; older logs lack it, so a strict upper bound is used instead:
    frames over the limit can only occur in seconds whose maximum exceeds it,
    and such a second holds at most interval/limit of them."""
    if all("p99" in f for f in frames):
        p99 = statistics.median(f["p99"] for f in frames)
        worst_p99 = max(f["p99"] for f in frames)
        return p99, worst_p99 < MAX_FRAME_P99_MS, f"per-second p99 median {p99:.1f}, worst {worst_p99:.1f}"
    total = sum(f["count"] for f in frames)
    over_seconds = sum(1 for f in frames if f["maximum"] > MAX_FRAME_P99_MS)
    bound = over_seconds * int(1000 // MAX_FRAME_P99_MS)
    passes = bound < 0.01 * total
    return None, passes, (f"bound: <= {bound} of {total} frames over {MAX_FRAME_P99_MS:.0f} ms "
                          f"({over_seconds} seconds with a max over the limit)")


def host_report(data: dict) -> bool:
    # Host frame/memory/queue fields are copied into every controller's record
    # for the same interval; count each host interval once.
    by_time = {}
    for series in data["soak"].values():
        for m in series:
            by_time.setdefault(m["host_monotonic_ns"] // NS_PER_MS, m)
    intervals = list(by_time.values())
    if not intervals:
        return False
    frames = [m["host_frame_ms"] for m in intervals if m["host_frame_ms"]["count"]]
    memory = sorted((m["host_monotonic_ns"], m["host_static_memory_bytes"]) for m in intervals)
    third = max(1, len(memory) // 3)
    early = statistics.median(v for _, v in memory[:third])
    late = statistics.median(v for _, v in memory[-third:])
    growth_pct = 100.0 * (late - early) / early
    drops = max(m["queue_drops"] for m in intervals)
    worst = max(f["maximum"] for f in frames)
    print("\nHost")
    print(f"  frame ms        median {statistics.median(f['median'] for f in frames):.1f}  "
          f"p95 {statistics.median(f['p95'] for f in frames):.1f}  worst {worst:.1f}")
    print(f"  static memory   {early / 1e6:.1f} MB -> {late / 1e6:.1f} MB ({growth_pct:+.2f}%)")
    print(f"  queue drops     {drops}")
    _, p99_ok, p99_text = frame_p99_verdict(frames)
    stall_ok = worst <= MAX_FRAME_MS
    print(f"  frame stall     worst {worst:.1f} ms [{'PASS' if stall_ok else 'FAIL'} <= {MAX_FRAME_MS:.0f} ms]; "
          f"p99 {p99_text} [{'PASS' if p99_ok else 'FAIL'} < {MAX_FRAME_P99_MS:.0f} ms]")
    return drops == 0 and growth_pct < 5.0 and stall_ok and p99_ok


def main() -> None:
    if len(sys.argv) not in (3, 4):
        raise SystemExit(__doc__)
    start_ns = int(float(sys.argv[2]) * NS_PER_S)
    end_ns = int(float(sys.argv[3]) * NS_PER_S) if len(sys.argv) == 4 else 2**63
    data = load(sys.argv[1], start_ns, end_ns)
    span = [m["host_monotonic_ns"] for series in data["soak"].values() for m in series]
    print(f"Window {start_ns / NS_PER_S:.1f}-{max(span) / NS_PER_S:.1f} s "
          f"({(max(span) - start_ns) / NS_PER_S:.0f} s)")
    active = [cid for cid in sorted(data["soak"]) if measurable(cid, data)]
    idle = [cid for cid in sorted(data["soak"]) if cid not in active]
    if idle:
        print(f"not measured (fewer than {MIN_INTERVALS} Connected intervals): {idle}")
    if not active:
        raise SystemExit("no controller has a measurable window")
    results = [controller_report(cid, data) for cid in active]
    results.append(host_report(data))
    print("\nTMB-022_SOAK_" + ("PASS" if all(results) else "FAIL"))


if __name__ == "__main__":
    main()
