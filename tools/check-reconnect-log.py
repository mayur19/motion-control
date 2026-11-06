#!/usr/bin/env python3
"""Check a host session JSONL for a timely same-reservation reconnect (TMB-021).

Usage: python3 -I tools/check-reconnect-log.py <session.jsonl>

Prints one line per check and exits 0 only if every check passes. Output holds
controller IDs, players, timings and rates only; endpoints are reduced to
"port changed" so LAN addresses are not copied into evidence.
"""
import json
import statistics
import sys

RESERVATION_MS = 15_000
MIN_MOTION_HZ = 80.0
RATE_WINDOW_INTERVALS = 5
EXPECTED_CHECKS = 10
NS_PER_MS = 1_000_000
SAME_EMISSION_NS = NS_PER_MS


def load_events(path: str) -> list:
    """Parse event records. Only an unterminated final line (a host killed
    mid-write) is tolerated and reported; any other bad line is fatal."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    truncated_tail = lines[-1] if lines else ""
    complete = lines[:-1]
    events = []
    for number, line in enumerate(complete, 1):
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise SystemExit(f"line {number}: invalid JSON ({error})")
        if record.get("record_type") == "event":
            events.append(record)
    if truncated_tail:
        print(f"NOTE  ignored unterminated final line {len(complete) + 1} ({len(truncated_tail)} bytes)")
    return events


def first(events, predicate, after_ns=-1):
    for event in events:
        if event["host_monotonic_ns"] > after_ns and predicate(event):
            return event
    return None


def is_event(name, **fields):
    def predicate(event):
        if event.get("event") != name:
            return False
        return all(event.get(key) == value for key, value in fields.items())
    return predicate


def same_clock_emission(connected: dict, sync: dict) -> bool:
    """One PONG emits one metrics signal: the connection manager (subscribed
    first) logs Connected/"clock synchronized" microseconds before the logger
    writes that same clock_sync. Only that case is accepted."""
    gap = sync["host_monotonic_ns"] - connected["host_monotonic_ns"]
    return connected.get("reason") == "clock synchronized" and 0 <= gap <= SAME_EMISSION_NS


def analyse(events):
    checks = []
    initial = first(events, is_event("pairing", reason="paired", player=1))
    if initial is None:
        return [("initial P1 pairing", False, "no pairing event with player=1")]
    cid = initial["controller_id"]
    checks.append(("initial P1 pairing", True, f"controller_id={cid}"))

    lost = first(
        events,
        lambda e: e.get("event") == "controller_state"
        and e.get("controller_id") == cid
        and e.get("state") in ("Paused", "Disconnected"),
        initial["host_monotonic_ns"],
    )
    checks.append(("Paused/Disconnected", lost is not None, lost and lost["state"]))
    if lost is None:
        return checks
    disconnected = first(
        events, is_event("controller_state", controller_id=cid, state="Disconnected"),
        initial["host_monotonic_ns"],
    ) or lost

    rehello = first(events, is_event("pairing", reason="reconnect"), lost["host_monotonic_ns"])
    if rehello is None:
        checks.append(("re-HELLO on new endpoint", False, "no reason=reconnect pairing"))
        return checks
    port_changed = rehello["endpoint"] != initial["endpoint"]
    checks.append(("re-HELLO on new endpoint", port_changed, "port changed" if port_changed else "same endpoint"))
    same = rehello["controller_id"] == cid and rehello["player"] == 1
    checks.append(("same controller ID and P1", same,
                   f"controller_id={rehello['controller_id']} player=P{rehello['player']}"))
    gap_ms = (rehello["host_monotonic_ns"] - disconnected["host_monotonic_ns"]) / NS_PER_MS
    checks.append(("within 15 s reservation", gap_ms <= RESERVATION_MS,
                   f"{gap_ms:.0f} ms after {disconnected['state']}"))

    t_rehello = rehello["host_monotonic_ns"]
    reconnecting = first(events, is_event("controller_state", controller_id=cid, state="Reconnecting"), t_rehello - 1)
    checks.append(("Reconnecting", reconnecting is not None, ""))
    sync = first(events, is_event("clock_sync", controller_id=cid), t_rehello)
    connected = first(events, is_event("controller_state", controller_id=cid, state="Connected"), t_rehello)
    fresh = sync is not None and int(sync.get("samples", 99)) <= 3
    checks.append(("fresh clock_sync/PONG", fresh, sync and f"samples={sync.get('samples')} rtt_ms={sync.get('rtt_ms'):.1f}"))
    ordered = bool(sync and connected and (
        sync["host_monotonic_ns"] <= connected["host_monotonic_ns"]
        or same_clock_emission(connected, sync)
    ))
    checks.append(("Connected after fresh sync", ordered,
                   connected and f"{(connected['host_monotonic_ns'] - t_rehello) / NS_PER_MS:.0f} ms after re-HELLO"))
    if not connected:
        return checks

    t_connected = connected["host_monotonic_ns"]
    gated = [
        e for e in events
        if e.get("event") == "soak_metrics" and e.get("controller_id") == cid
        and t_rehello < e["host_monotonic_ns"] < t_connected
    ]
    leaked = [e for e in gated if e.get("received_motion_hz", 0) > 0 and e.get("connection_state") != "Connected"]
    checks.append(("no motion accepted before sync", not leaked,
                   f"{len(gated)} gated interval(s), {len(leaked)} with accepted motion"))
    rates = [
        e["received_motion_hz"] for e in events
        if e.get("event") == "soak_metrics" and e.get("controller_id") == cid
        and e["host_monotonic_ns"] > t_connected + NS_PER_MS * 1000
    ][:RATE_WINDOW_INTERVALS]
    median = statistics.median(rates) if rates else 0.0
    checks.append((f"motion resumes > {MIN_MOTION_HZ:.0f}/s", median > MIN_MOTION_HZ,
                   f"median {median:.1f} Hz over {len(rates)} interval(s)"))
    return checks


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    checks = analyse(load_events(sys.argv[1]))
    for name, passed, detail in checks:
        print(f"{'PASS' if passed else 'FAIL'}  {name}: {detail or ''}")
    ok = bool(checks) and all(passed for _, passed, _ in checks) and len(checks) == EXPECTED_CHECKS
    print("TMB-021_PHYSICAL_RECONNECT_OK" if ok else "TMB-021_PHYSICAL_RECONNECT_INCOMPLETE")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
