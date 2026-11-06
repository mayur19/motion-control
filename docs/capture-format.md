# Labeled motion capture format (v1)

TMB-029. A capture is a directory
`~/Library/Application Support/Godot/app_userdata/Motion Badminton Host/captures/<capture_id>/`
(`user://captures` in Godot) written by the host capture panel (**F6**).

| File | Mutability | Content |
| --- | --- | --- |
| `raw.jsonl` | Immutable after stop | Header, then every accepted datagram byte-exact |
| `raw.sha256` | Written once at stop | `<sha256>  raw.jsonl` (`shasum -a 256 -c` compatible) |
| `labels.jsonl` | Append-only | Labels header, then take records; corrections append revisions |

## raw.jsonl

Line 1 is the header:

```json
{"record":"capture_header","capture_format":1,"capture_id":"cap_…","started_utc":"…",
 "host_version":"0.1.0-dev","metadata":{"source":"host capture panel"}}
```

Every further line is one datagram that passed the host's pairing, endpoint
and session gates, in arrival order:

```json
{"record":"datagram","arrival_monotonic_ns":123,"endpoint":"192.168.1.20:52000","bytes_b64":"…"}
```

Only protocol v1 `MOTION` and `CALIBRATION` datagrams are recorded
(`MotionIngest.datagram_accepted`). `HELLO` (which carries the pairing
secret), `STATUS`, `PING/PONG` and other control traffic are never stored.
Captures contain no account, device serial or installation identifiers; the
`phone` label is operator-chosen text. `arrival_monotonic_ns` uses the host's
monotonic clock (same clock as take boundaries).

## labels.jsonl

```json
{"record":"labels_header","capture_format":1,"capture_id":"cap_…"}
{"record":"take","take_id":1,"revision":1,"player":1,"phone":"iPhone","handedness":"right",
 "intended_shot":"smash","valid":true,"start_arrival_ns":…,"end_arrival_ns":…}
```

- `player`: `1` or `2`. `phone`: 1–32 letters, digits, space, `_` or `-`.
- `handedness`: `right` or `left`.
- `intended_shot`: `smash`, `clear`, `drop`, `lift`, `other_swing`, or a
  non-swing take: `idle`, `handling`, `walking`.
- `valid`: `false` marks an unsafe, ambiguous or incorrectly performed take;
  it is kept, never deleted.
- The effective label of a take is its highest `revision`. Correct labels with
  `python3 -I tools/capture-labels.py correct <dir> --take N --set intended_shot=clear`,
  which appends a new revision and never touches `raw.jsonl`.

## Replay

```sh
godot --headless --path apps/host-godot --script res://replay/replay_capture.gd -- \
  --capture=<capture dir> --output=<result.json> [--config=<detector config.json>]
```

Replay needs no phone or network. It refuses a capture whose `raw.sha256`
does not match, then feeds each datagram through a fresh `MotionIngest`
(same codec and calibration normalizer as live) into the same
`DetectorPipeline` class the live host uses. Identical capture and detector
configuration give an identical result. The result JSON (`result_format` 1)
contains `capture_id`, `raw_sha256`, `detector` (name, version and full
configuration), `totals`, per-take summaries (effective labels, normalized
sample count, peak angular speed, detector event count and first-event time
after take start) and every detector event.

The live host logs the same detector's configuration (`detector_config`) and
events (`detector_event`) in the session log. Until TMB-032 the detector is a
placeholder (`angular_speed_probe`: rising normalized angular-speed threshold
with a refractory period), not the swing detector.
