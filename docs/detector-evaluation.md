# Detector evaluation and tuning reports (TMB-033)

`tools/detector-evaluation.py` evaluates one dataset split at a time through
the same `DetectorPipeline` used live. It verifies each capture checksum,
uses the latest label revision, rejects stale replay output, and embeds the
exact resolved detector and preprocessing description in JSON and Markdown.

## Tune workflow

Create a detector input configuration, then run only the tune split while
comparing candidates:

```sh
python3 -I tools/detector-evaluation.py "$CAPTURE_ROOT" \
  --split tune --config detector-config.json \
  --json tmb-033-tune.json --markdown tmb-033-tune.md
```

Without `--results-dir`, the tool runs
`apps/host-godot/replay/replay_capture.gd` for every session in the selected
split and requests its per-sample series. The input config may omit defaults;
the report always stores the full resolved `DetectorPipeline.describe()`
value returned by replay, including preprocessing.

To report already-generated outputs, put `<capture_id>.json` and
`<capture_id>.series.jsonl` in one directory and use `--results-dir DIR`.
Series generated for TMB-033 must include `arrival_monotonic_ns`; regenerate
older TMB-031 series files that predate this field.

## Held-out workflow

Freeze the configuration after tune results are accepted. Evaluate held-out
sessions once, save both report files as versioned evidence, and do not use
their results to change thresholds:

```sh
python3 -I tools/detector-evaluation.py "$CAPTURE_ROOT" \
  --split heldout --confirm-heldout --config frozen-detector-config.json \
  --json tmb-033-heldout-v1.json --markdown tmb-033-heldout-v1.md
```

The explicit `--confirm-heldout` makes accidental inspection harder, and the
tool requires both JSON and Markdown archive paths and refuses to overwrite
either file for held-out runs. Process discipline and the archived report
provide the one-time boundary. A later detector change requires a newly
designated held-out dataset, not another optimization pass over the original
held-out sessions.

Sessions assigned `exclude` and takes whose effective label has
`valid=false` do not contribute to metrics and are listed in the report.
Unassigned captures, checksum mismatches, stale effective labels, and mixed
pipeline descriptions stop the run instead of silently producing metrics.

## Matching and metrics

Swing labels contain a count for the whole take, not timestamps for each
swing. Matching is therefore count-based per take:

- `TP = min(swing_count, detector events)`
- `FN = max(swing_count - detector events, 0)`
- `FP = max(detector events - swing_count, 0)`
- every event in an `idle`, `handling`, or `walking` take is an FP

This cannot tell which particular swing was detected. A missed real swing and
an extra trigger elsewhere in the same take can cancel in the count. That is
why the report presents per-take values before aggregation and keeps every
phone, player, hand, shot, and speed subgroup visible. False triggers per 10
minutes use only events and duration from non-swing takes; swing over-triggers
still count against precision.

## Trigger-to-peak estimate

For each trigger, the tool selects the maximum preprocessed angular speed
after the trigger and before the first of: the next trigger from that
controller, the end of the take, or 1000 ms. Positive milliseconds mean the
trigger leads that following peak.

This is an event-to-signal estimate, not ground-truth swing timing. With no
per-swing timestamp, an extra trigger can be associated with a minor peak,
the selected peak can be a backswing, and a trigger after the intended
physical peak will instead see a later peak. Consequently this rule cannot
reliably measure negative lag or resolve the open backswing-versus-forward-
swing question; annotated captures or per-swing timing labels would be needed
for that.

Synthetic pytest fixtures verify calculations and guardrails. They are not
physical performance evidence. TMB-033 acceptance remains pending the real
TMB-030 held-out sessions and the separate live idle/handling check.
