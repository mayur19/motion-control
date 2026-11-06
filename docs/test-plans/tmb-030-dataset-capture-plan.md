# TMB-030 baseline dataset — capture plan

Status: draft for owner review (2026-11-06). Tooling: host capture panel
(F6, `docs/capture-format.md`) and `tools/dataset-inventory.py`.

## Constraints

- One operator (the owner). Sessions must stay short: the owner has said
  10-minute sessions are too long, so every session here is **≤ 6 minutes**
  including pairing and calibration.
- iPhone 17e is always available. The Galaxy M14 is borrowed and only
  intermittently available, so Galaxy sessions are batched whenever it is
  on hand.
- Only one player is available. "Both intended players" (step 2) is a
  recorded gap unless a second person joins a session.

## Targets per phone (ticket minimums)

| Data | Minimum | Plan |
| --- | --- | --- |
| Genuine swings | 100 | 4 swing sessions × ~28 = ~112 |
| Non-swing time (idle, menu, handling, walking) | 20 min | 4 × 1 min + 4 × 5 min = 24 min |
| Held-out sessions | separated by session | 1 swing + 1 non-swing session per phone, assigned before recording |

Per phone this is 8 sessions (~48 min). For both phones it's 16 sessions,
for example two 6-minute sessions a day over 8 days. Sessions can be spread
over any number of days; nothing needs to happen in one sitting.

## Session types

Before every session: clear the space (laptop, people, pets, fragile
objects), use the wrist strap, then on the host press **F6 → START
CAPTURE** *before* pairing, then pair and calibrate.

### S — swing session (≤ 6 min, ~28 swings)

| Take | Labels | Content |
| --- | --- | --- |
| 1 | `smash`, speed `gentle` then `normal` | 7 swings |
| 2 | `clear` | 7 swings |
| 3 | `drop` | 7 swings |
| 4 | `lift` | 7 swings |
| 5 | `handling` | ~1 min: adjust grip, lower the phone, pick it up again |

- Set **Swings in take** to the number actually performed. Mark a take
  **invalid** (never delete it) if a swing was unsafe, ambiguous or
  performed incorrectly.
- Speeds: `gentle` (controlled), `normal` (game speed) and, only when the
  space is clear, `fast` (brisk but still controlled, never maximum force).
  Rotate the speed across sessions so each shot gets every speed.
- Hand: right by default. If you're comfortable, make one S session per
  phone left-handed; it counts toward the 100.

### N — non-swing session (≤ 6 min, ~5 min of data)

| Take | Label | Content |
| --- | --- | --- |
| 1 | `idle` | 2 min holding the phone in the racket grip, relaxed |
| 2 | `handling` | 1.5 min: menu use on the laptop, grip changes, setting the phone down and picking it up |
| 3 | `walking` | 1.5 min walking around the room holding the phone |

Optional low-effort extra: one long `idle` take while doing desk work with
the phone in hand or in a pocket. It's passive, so it doesn't count against
the session length limit.

## Train/tune vs held-out split

The split is by recording session, never by individual swing, and is
decided **before** recording so tuning can't influence it. Per phone:

| Session | Split |
| --- | --- |
| S1, S2, S3, N1, N2, N3 | `tune` |
| S4, N4 | `heldout` |

The assignment is stored in `dataset-splits.json` next to the captures and
checked by `tools/dataset-inventory.py`.

## If the full volume isn't possible

A smaller dataset can still move M2 forward, but the owner should accept the
consequences explicitly (record it in the TMB-030 implementation log):

- TMB-033 requires ≥ 95% real-swing detection on held-out data. With ~28
  held-out swings per phone, each miss costs ~3.6 points, so the result is a
  coarse estimate. With fewer held-out swings it can't distinguish 95% from
  90%.
- TMB-033 also requires < 1 false swing per 10 minutes of idle/handling. ~5
  held-out non-swing minutes per phone can show a gross false-positive
  problem but can't demonstrate that rate. The live 10-minute check would
  have to be accepted on shorter evidence or deferred.
- Possible reduced minimum (owner decision): 60 swings and 10 non-swing
  minutes per phone (S1–S3 tune, S4 held-out with ~16 swings; N1–N2).

## Privacy

Captures contain only motion/calibration datagrams, operator-chosen labels
(`phone` is a short label like `iPhone`) and host timing. They have no
account, name, serial or installation identifiers. Raw captures stay in the
host's user-data folder and are not committed. Only the inventory and SHA-256
checksums are committed as evidence.
