# TMB-033 detector evaluation — tune

This report is computed evidence for the named dataset split. Synthetic fixture results are not physical evidence.

## Pipeline configuration

```json
{
  "config": {
    "max_shaft_fraction": 1.0,
    "min_rise_rad_s2": 20.0,
    "onset_speed_rad_s": 9.5,
    "rearm_speed_rad_s": 1.5,
    "refractory_ms": 700,
    "rise_window_ms": 40
  },
  "detector": "early_rise",
  "preprocessing": {
    "config": {
      "cutoff_hz": 25.0,
      "max_gap_ms": 50
    },
    "name": "one_pole_lowpass",
    "version": 1
  },
  "version": 1
}
```

## Count-based matching

TP=min(expected swings, triggers); FN=max(expected-triggers, 0); FP=max(triggers-expected, 0). Every trigger in a non-swing take is an FP.

Swing labels contain counts, not per-swing timestamps; individual triggers cannot be matched to specific swings, and a miss plus an extra trigger can cancel in the count.

## Overall metrics

| TP | FN | FP | Recall | Precision | Non-swing min | False triggers / 10 min |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 86 | 4 | 3 | 0.956 | 0.966 | 19.78 | 0.506 |

## Per-take metrics

| Capture | Take | Shot | Expected | Events | TP | FN | FP | Median trigger-to-peak ms |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| cap_20261106T153652_4e77e74b | 1 | smash | 11 | 10 | 10 | 1 | 0 | 149.858 |
| cap_20261106T153652_4e77e74b | 2 | clear | 8 | 7 | 7 | 1 | 0 | 109.894 |
| cap_20261106T153652_4e77e74b | 3 | drop | 8 | 9 | 8 | 0 | 1 | 59.943 |
| cap_20261106T153652_4e77e74b | 4 | lift | 7 | 6 | 6 | 1 | 0 | 159.847 |
| cap_20261106T153652_4e77e74b | 5 | handling | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261106T155237_bce07b0d | 1 | idle | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261106T155237_bce07b0d | 2 | handling | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261106T155237_bce07b0d | 3 | walking | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261107T043308_6e5dab2c | 1 | smash | 7 | 7 | 7 | 0 | 0 | 49.954 |
| cap_20261107T043308_6e5dab2c | 2 | clear | 7 | 7 | 7 | 0 | 0 | 69.935 |
| cap_20261107T043308_6e5dab2c | 3 | drop | 7 | 7 | 7 | 0 | 0 | 59.944 |
| cap_20261107T043308_6e5dab2c | 4 | lift | 7 | 7 | 7 | 0 | 0 | 29.971 |
| cap_20261107T043308_6e5dab2c | 5 | handling | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261107T044259_1ca96db6 | 1 | idle | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261107T044259_1ca96db6 | 2 | handling | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261107T044259_1ca96db6 | 3 | walking | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261107T045405_f44c8d90 | 1 | smash | 7 | 7 | 7 | 0 | 0 | 229.772 |
| cap_20261107T045405_f44c8d90 | 2 | clear | 7 | 8 | 7 | 0 | 1 | 264.736 |
| cap_20261107T045405_f44c8d90 | 3 | drop | 7 | 7 | 7 | 0 | 0 | 79.92 |
| cap_20261107T045405_f44c8d90 | 4 | lift | 7 | 6 | 6 | 1 | 0 | 224.784 |
| cap_20261107T045405_f44c8d90 | 5 | handling | 0 | 1 | 0 | 0 | 1 | 0 |
| cap_20261107T050502_12dffc93 | 1 | idle | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261107T050502_12dffc93 | 2 | handling | 0 | 0 | 0 | 0 | 0 | n/a |
| cap_20261107T050502_12dffc93 | 3 | walking | 0 | 0 | 0 | 0 | 0 | n/a |

## Subgroups

Every available phone, player, hand, shot and speed subgroup is shown below.

### Phone

| Value | TP | FN | FP | Recall | Precision | False triggers / 10 min |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| iPhone | 86 | 4 | 3 | 0.956 | 0.966 | 0.506 |

### Player

| Value | TP | FN | FP | Recall | Precision | False triggers / 10 min |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 86 | 4 | 3 | 0.956 | 0.966 | 0.506 |

### Hand

| Value | TP | FN | FP | Recall | Precision | False triggers / 10 min |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| right | 86 | 4 | 3 | 0.956 | 0.966 | 0.506 |

### Shot

| Value | TP | FN | FP | Recall | Precision | False triggers / 10 min |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| clear | 21 | 1 | 1 | 0.955 | 0.955 | n/a |
| drop | 22 | 0 | 1 | 1 | 0.957 | n/a |
| handling | 0 | 0 | 1 | n/a | 0 | 1.134 |
| idle | 0 | 0 | 0 | n/a | n/a | 0 |
| lift | 19 | 2 | 0 | 0.905 | 1 | n/a |
| smash | 24 | 1 | 0 | 0.96 | 1 | n/a |
| walking | 0 | 0 | 0 | n/a | n/a | 0 |

### Speed

| Value | TP | FN | FP | Recall | Precision | False triggers / 10 min |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fast | 27 | 1 | 1 | 0.964 | 0.964 | n/a |
| gentle | 28 | 0 | 0 | 1 | 1 | n/a |
| none | 0 | 0 | 1 | n/a | 0 | 0.506 |
| normal | 31 | 3 | 1 | 0.912 | 0.969 | n/a |

## Trigger timing estimate

For each trigger, select the maximum preprocessed angular speed after that trigger, before the next trigger from the same controller, take end, or 1000 ms.

Positive milliseconds mean the trigger leads the following peak.

This is an event-to-signal estimate, not ground-truth swing timing. Extra triggers, backswing peaks and missing per-swing timestamps can associate the wrong peak; lag after an already-passed physical peak is not observable with this rule.

Samples: 89; mean 132.681 ms; median 89.914 ms; range 0–519.484 ms.

## Exclusions

Exclude-split sessions: cap_20261106T143432_8de45fcc, cap_20261106T143914_16e061f4, cap_20261107T044053_402c4bb4, cap_20261107T050142_4eaf2c13, cap_20261107T050227_86bdc366.

Invalid takes: none.
