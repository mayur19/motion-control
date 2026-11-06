# Synthetic motion packet generator

Emits valid protocol v1 `MOTION` datagrams with deterministic sine-wave sensor
values. It supports one or two controllers plus seeded loss, duplication,
reordering, fixed delay and deliberately invalid packets.

## Clean 200 Hz run

```sh
ruby tools/packet-generator/motion_packet_generator.rb \
  --host 127.0.0.1 --port 7000 --rate 200 --duration 10 --controllers 2
```

## Deterministic impairment run

```sh
ruby tools/packet-generator/motion_packet_generator.rb \
  --host 127.0.0.1 --port 7000 --rate 200 --duration 10 --controllers 2 \
  --seed 42 --loss 0.05 --duplicate 0.03 --reorder 0.04 \
  --delay-ms 8 --invalid-every 50
```

Use `--dry-run` to exercise generation without opening a socket. Use
`--no-pace` with `--dry-run` to validate a long logical run quickly; timestamps
still advance at the configured sample interval. The last output line begins
with `TMB_GENERATOR_SUMMARY` followed by machine-readable JSON.

The summary includes both configured impairment events and receiver-observable
counters: `valid_duplicates_emitted`, `reordered_valid_datagrams` and
`expected_detectable_loss`. These account for overlap between loss, invalid and
reorder modes and are the values a strict receiver should report.

Run `--help` for all options. Rates and probabilities are per controller. A
valid packet is decoded by the tool's strict motion validator before any
intentional invalid mutation is applied.
