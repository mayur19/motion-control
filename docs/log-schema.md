# Host session log schema v1

Host engineering logs use UTF-8 JSON Lines (`.jsonl`): one complete JSON object
per line, terminated by LF. A reader must ignore an incomplete final line, so a
crash cannot invalidate earlier records.

## Common fields

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | integer | Exactly `1` |
| `record_type` | string | `session_header`, `packet` or `event` |
| `session_id` | string | Host engineering-session identifier |

Unknown fields must be ignored. A new incompatible record shape requires a new
schema version.

## Session header

The first record is `session_header`. It contains application/Godot versions,
protocol version, OS/model metadata, wall-clock start time, host monotonic start
time, test metadata and the privacy declaration.

## Packet record

Every observed UDP datagram produces a `packet` record with:

- sender `endpoint`;
- `arrival_monotonic_ns`;
- `packet_size`;
- `validation`, either `OK` or a protocol rejection code;
- for valid packets: message, session/controller identifiers and sequence;
- for valid sensor packets: native `sensor_monotonic_ns`.

The log does not delay or change packet acceptance. Raw datagram bytes are not
stored by this logger.

## Event record

An `event` has an `event` name, `host_monotonic_ns` and event-specific fields.
Names are stable snake-case identifiers such as `host_started`, `queue_drop` or
`logging_disabled`.

The `clock_sync` event includes `controller_id`, `samples`, `rtt_ms`,
`offset_ms`, `drift_ppm`, and `backward_corrections`. Motion samples inside the
host pipeline additionally carry `clock_synchronized`,
`adjusted_host_monotonic_ns`, and `adjusted_sample_age_ms`; unsynchronized age is
`-1` rather than a misleading wall-clock calculation.

The `controller_state` event includes `controller_id`, the new `state` and a
machine-readable `reason`. It records pairing/reconnect clock gates, background
pauses, invalid sensor reports, heartbeat degradation/disconnect and recovery.

The `pairing` event records every HELLO outcome: `controller_id`, assigned
`player` (0 when rejected), WELCOME session `state`, `reason` (`paired`,
`retry`, `reconnect`, `expired`, `full`, `wrong_session` or `wrong_secret`), the
source `endpoint` and `platform`. Fields are allow-listed; pairing secrets,
installation identities and device models are never written.

The `awdl_state` event records the macOS AWDL interface state (`active`,
`inactive` or `absent`) at host start and on every change; while `active` on a
Wi-Fi host, controller input is expected to show periodic ~100 ms delays (see
`docs/development.md`).

The `calibration` event records each accepted controller `CALIBRATION`:
`controller_id`, `handedness` (`right` or `left`), `neutral_orientation`
(x, y, z, w), `acceleration_bias`, `gyroscope_bias`, `quality` and the native
`sensor_monotonic_ns`. It lets physical runs check calibration repeatability;
the raw packet records are unchanged.

The once-per-second `soak_metrics` event records controller-reported sensor Hz,
accepted motion Hz, cumulative loss/duplicate/reorder totals, jitter, clock
RTT/offset/drift, sample-age and host-frame-time distributions (each with
`count`, `median`, `p95`, `p99` and `maximum`), static memory, queue depth/drops and connection state. Arrays are reduced and cleared
each interval, so this telemetry has bounded memory use.

The `raw_latency_stimulus` event identifies the controller and sequence and
contains sensor, adjusted-sample, arrival, threshold, simulation-marker and
next-frame render-marker monotonic timestamps, plus the configured/measured
angular speed and calculated software sample-to-render time.

## Flush, bounds and privacy

- The writer flushes at least every second and again on clean close.
- A configured byte ceiling is checked before every complete line. On reaching
  it, the writer flushes and closes; later records are ignored. The file never
  exceeds the ceiling.
- Logging can be disabled before the session; disabled mode creates no file.
- Logs contain motion and network engineering metadata only. Audio, video,
  pairing secrets and personal account data are prohibited.
