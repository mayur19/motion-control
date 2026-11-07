# External dataset evaluation (TMB-033 applicability spike)

**Status:** Stage 1 (repository-only applicability review) done 2026-11-07.
Stage 2 (sample inspection) waits for an owner decision. No external data has
been downloaded, inspected or committed.

**Scope:** an off-domain robustness check for the TMB-032 `early_rise`
detector. It is supplementary evidence. It is not a replacement for TMB-030,
not part of the tune/held-out split, and not a new ticket.

**Machine-readable source manifest:** `docs/external-dataset-sources.json`.

## 1. The question

The question is not "what is detector recall on 848 more swings?" It is:

> Can a public badminton sensor stream be interpreted honestly enough to run a
> meaningful external sensitivity/morphology check of a detector built for a
> phone held as the racket handle?

If the answer is no, an external number would be worse than none: it would
look like evidence and mean nothing.

## 2. Result categories (strict separation)

Every detector result in this project belongs to exactly one category. Reports
must name the category in their title and never combine categories into one
aggregate.

| Category | Source | May tune on it? | What it can support |
| --- | --- | --- | --- |
| `internal tune` | TMB-030 sessions with split `tune` | Yes | Threshold selection, diagnostics |
| `internal heldout` | TMB-030 S4/N4 (`heldout`), evaluated once with `--confirm-heldout` | **No** | TMB-033 acceptance (recall, false triggers per 10 min) |
| `external/off-domain` | Public datasets (this document) | **No** (see below) | Morphology and sensitivity questions only; never acceptance |

Rules for the external category:

- External results never change a held-out decision and are never computed
  from, merged with or compared to held-out reports before the one-time
  held-out evaluation has been archived.
- No detector threshold is changed because of an external result unless a
  separate, owner-approved, evidence-backed domain mapping exists (Section 6),
  and that change would then require a fresh internal tune run. The current
  internal held-out boundary is unchanged either way.
- External reports carry the dataset name, version, archive hash, adapter
  version and the exact `DetectorPipeline.describe()` value. They are written
  to a separate path from TMB-033 internal reports.
- Nothing in an external report is a physical or product performance claim
  for the phone controllers.

## 3. BadminSense / BADS_CLL

Primary sources:

- Dataset repository: <https://github.com/taizhouchen/BadminSense_Dataset>
  (README reviewed at commit `0408092f7c54b9cb2a53a0605a1d08b2f286f966`,
  2026-04-08).
- Paper: T. Chen, K. Chen, X. Liu, P. Ke, Z. Sun, "BadminSense: Enabling
  Fine-Grained Badminton Stroke Evaluation on a Single Smartwatch", CHI 2026,
  <https://arxiv.org/abs/2603.21825>.

### 3.1 What the README states

- Name and version: `BADS_CLL_OPENACCESS_V1`, "Version 1.0", about 14 GB,
  one Google Drive `.zip`.
- 848 valid stroke samples with IMU and audio data, a GIF clip per stroke,
  player information and three labels: `Stroke Type`, `Stroke Quality Rating`
  and `Impact Location`.
- 96 folders. Each one is one player, one stroke type and one `Section`, with
  up to 10 valid strokes. The folder name is
  `Gender_Exp_StrokeType_PlayerCode_Section_Device`.
- One `.json` per section. Each stroke entry has:
  - `Info`: `recordName`, `gender`, `exp` (Low/Medium/High), `section`,
    `startTimestamp`, `endTimestamp`;
  - `Label`: `positionX` [-1, 1], `positionY` [0, 1], `actionType`,
    `actionEval` (a quality rating from 7 experienced players);
  - `Data`: `ACCELEROMETER`, `GYROSCOPE`, `GYROSCOPE_UNCALIBRATED` (with
    drift), `MAGNETIC_FIELD`, `MAGNETIC_FIELD_UNCALIBRATED` (with bias),
    `ROTATION_VECTOR` (with cos delta and heading accuracy) and `AUDIO`, each
    with timestamps.
- IMU at 100 Hz, microphone at 16 kHz.
- Stroke labels: `BackhandTransition` (paper BOC), `ForehandHigh` (FOC),
  `ForehandLob` (FOD), `ForehandKill` (FOS).
- **No units, coordinate frame, timestamp unit or epoch are documented.**
  The README does not say whether `Data` holds only the stroke window or the
  whole section stream.

### 3.2 What the paper reports (not yet verified against the data)

- Samsung Galaxy Watch 6 FE (42 and 48 mm) running Wear OS, worn on the
  dominant wrist. The mounting orientation is shown only in a figure.
- 12 participants, all right-handed (10 male, 2 female), mixed skill levels.
  The introduction calls them experienced, but Section 4 calls them amateurs.
- Structured drill on a standard court: a facilitator served, and each
  participant repeated each of the 4 strokes 20 times (960 attempts, 848
  valid). Real racket and real shuttle impacts.
- Their segmentation uses 2000 ms windows around a local maximum of squared
  sensor values, plus an audio-energy check to reject swings that miss the
  shuttle. No idle, handling or non-stroke recordings are described.
- Their models low-pass filter (20 Hz) and later upsample to 500 Hz. Whether
  the published JSON is raw or processed is not stated.

The sensor names match the Android sensor framework (`TYPE_GYROSCOPE_UNCALIBRATED`
and so on). If so, `ACCELEROMETER` would include gravity, gyroscope values
would be rad/s, and timestamps might be nanoseconds since boot. **This is a
hypothesis to check, not a fact to build on.**

### 3.3 License

The README states CC BY-NC-ND 4.0
(<https://creativecommons.org/licenses/by-nc-nd/4.0/legalcode>) and adds that
users must "not modify or use them for commercial purposes in any way". The
GitHub API reports no SPDX license for the repository. The arXiv paper itself
is CC BY 4.0, which does not cover the dataset.

Consequences for this project (an engineering reading, not legal advice):

- **Non-commercial:** the PRD does not say whether the game will be
  commercial; the Architecture plan defers monetization and app-store
  distribution beyond Release 1. If the product, or a later version, is
  commercial, using this data to make product decisions
  such as threshold choices may conflict with NC. **This is the owner's
  call.**
- **No-derivatives:** sharing adapted material is prohibited, and the README's
  wording is stricter than the CC deed. Derived samples, converted files,
  plots of the raw signals and per-stroke tables must not be committed or
  shared. Aggregate descriptive statistics in a private report are the most
  that should be considered, and only after the owner accepts the terms.
- **Attribution:** any report must cite the paper.
- Source data, derived samples, GIFs and audio are never committed. That
  matches the Architecture plan's rule that logs carry no audio or video.

## 4. Domain gaps compared with the phone controller

| Aspect | BadminSense | This product |
| --- | --- | --- |
| Device | Galaxy Watch 6 FE (reported) | iPhone 17e, and an Android phone (PRD: Pixel 10 Pro; current test phone: Galaxy M14) |
| Placement | Dominant wrist, on the forearm side of the wrist joint | Phone gripped as the racket handle; it *is* the racket |
| Body segment | Forearm. Wrist flexion and forearm rotation move the racket relative to the watch | Racket. Wrist action is included in the measured rotation |
| Angular velocity | Forearm angular velocity. Its magnitude is mounting-invariant, but it is not racket angular velocity | Racket angular velocity in the common racket frame (TMB-026) |
| Acceleration | Probably total acceleration including gravity (unconfirmed) | Gravity-free linear acceleration (required by TMB-026) |
| Frame and calibration | Watch body axes; mounting orientation unknown; no grip calibration | Calibrated common racket frame (TMB-027/028); raw axes kept separately |
| Sampling | 100 Hz per README; jitter, gaps and duplicates unknown | iPhone 100 Hz, Android up to 250 Hz, jitter handled by preprocessing |
| Clock | Unknown timestamp units and epoch | Controller monotonic ns, plus synchronized host arrival time |
| Motion | Real racket, real shuttle impact, served drill, overhead strokes | Air swing with a phone, no impact, safety-limited intensity, smash/clear/drop/lift |
| Strokes | 4 overhead strokes (3 forehand, 1 backhand); no lift/underhand | smash, clear, drop, lift (underhand) |
| Players | 12 right-handed | Currently 1 right-handed player; left hand is planned |
| Segmentation | Pre-segmented valid strokes (impact present) | Continuous streams with idle, handling and walking |
| Labels | Stroke type, quality rating, impact location | Shot, speed, hand, player, swing count per take |

Implications:

- **Threshold values do not transfer.** `onset_speed_rad_s` (9.5) and
  `min_rise_rad_s2` (20) were tuned on calibrated racket-frame angular speed.
  Forearm angular speed at the wrist is a different quantity. A miss or hit at
  9.5 rad/s on watch data says nothing direct about the phone.
- **Placement-robust signals are the honest starting point**: angular-speed
  magnitude (independent of mounting rotation), its peak, rise-rate
  distribution and the time from first rise to peak. These describe stroke
  morphology, not product performance.
- **The common racket frame must not be applied.** No axis transform from
  watch axes to `+X_R/+Y_R/+Z_R` is defined or justified. The calibration
  normalizer and `DetectorPipeline` require calibrated samples and must not
  receive fabricated calibration.
- **Impact shock** in real strokes is a feature the phone stream never has.
  It can create a speed or acceleration spike near the peak that an air swing
  lacks.

## 5. Why valid strokes cannot measure false triggers

TMB-033 acceptance has two parts: recall of at least 95% on held-out data, and
fewer than one false swing per 10 minutes of live idle/normal handling.
BADS_CLL cannot address the second part:

- It publishes only strokes that passed validation (impact present,
  labelable). No idle, menu, walking, handling or missed-swing time is
  published, so there is no non-swing denominator.
- Even if `Data` turns out to cover the whole section stream, the time between
  strokes is a player waiting for the next serve on court, not a person
  holding a phone controller in a living room. It is not the TMB-030
  `idle`/`handling`/`walking` distribution and must not be reported as false
  triggers per 10 minutes.
- Validation removed failed or unlabelable attempts (960 attempted, 848
  valid), so the stroke set is biased toward clean strokes.
- Recall on pre-segmented windows also flatters precision: a detector that
  fires on any motion scores 100% recall there.

At most, the dataset can answer narrow **sensitivity/morphology** questions:
for example, whether forearm angular speed in real overhead strokes shows a
backswing rise before the forward swing (the open TMB-032 question), and how
long the rise-to-peak interval is across 12 players. Even these are about the
forearm, not the racket.

## 6. Metadata to confirm from a real sample before any adapter

An adapter may be written only after **every** item below is answered from a
real file, recorded in the TMB-033 log, and checked against the paper:

1. **Timestamp units and epoch** for each stream, and for `startTimestamp` /
   `endTimestamp`: ns or ms, boot or wall clock, and whether stream and stroke
   timestamps share a clock.
2. **Sample rate and jitter:** the measured interval distribution per stream,
   compared with the stated 100 Hz.
3. **Sensor units:** gyroscope rad/s or deg/s; accelerometer m/s² or g, and
   whether it includes gravity.
4. **Coordinate convention:** watch body axes, handedness, sign, and which
   wrist and orientation the watch was worn in; whether this varies by player
   or `Device`.
5. **Calibration status:** whether `GYROSCOPE` is bias-corrected (compare with
   `GYROSCOPE_UNCALIBRATED` drift), and whether any filtering, resampling or
   interpolation was applied before publication.
6. **Segment boundaries:** whether `Data` is the stroke window, the whole
   section, or something else; how start and end relate to the swing and the
   impact; and how much pre-swing time precedes the rise (`early_rise` needs
   history before onset).
7. **Missing and duplicate samples:** gaps, repeated timestamps, unordered
   samples, and per-stream length mismatches.
8. **Archive identity:** the exact archive name, size and SHA-256, plus the
   dataset version string, recorded before any processing.

Until these are known, nothing from BADS_CLL may enter `DetectorPipeline`.

## 7. Other public datasets (later candidates, not detector inputs)

None of these can validate TMB-032 trigger thresholds. Their licenses have
not been reviewed.

| Dataset | Content | Possible later use |
| --- | --- | --- |
| MultiSenseBadminton — <https://github.com/dailyminiii/MultiSenseBadminton> (data: <https://doi.org/10.6084/m9.figshare.c.6725706.v1>) | 7,763 forehand-clear/backhand-drive swings from 25 players: body tracking, EMG, eye tracking, foot pressure | Biomechanics across skill levels and later shot intent (TMB-034). Not a phone or racket-handle stream |
| ShuttleSet — <https://github.com/wywyWang/CoachAI-Projects/tree/main/ShuttleSet> | Tactical stroke-by-stroke match annotations; no controller IMU | Shot taxonomy, rally structure and AI opponent (TMB-041) |
| BFMD — <https://ning-d.github.io/BFMD-Dataset/> | Broadcast video, pose, shuttle trajectories and shot labels | Shuttle trajectory and outcome tuning (TMB-037, TMB-046/047) |
| Mendeley frame-level badminton motion — <https://data.mendeley.com/datasets/3sp4xntp34/1> | Video frames, not IMU | Shot taxonomy reference only |
| VideoBadminton — <https://github.com/qilimk/VideoBadminton> | Fine-grained video action recognition, not IMU | Shot taxonomy reference only |

## 8. Recommendation

**Defer.** Do not download the 14 GB archive yet. Proceed to a minimal sample
inspection only after both owner conditions below are met.

License reasons:

- CC BY-NC-ND 4.0, with README wording that forbids modification "in any
  way", conflicts with any commercial use and with sharing derived material.
  Whether the product's intended use is non-commercial is an owner decision
  that has not been made. If it may become commercial, reject the dataset for
  product decisions.

Technical reasons:

- Wrist-worn forearm motion with real shuttle impact, compared with an air
  swing of a phone that is the racket: thresholds cannot transfer, and no
  defensible axis mapping exists.
- Units, timestamps, frame, calibration status and segment boundaries are
  undocumented (Section 6).
- Valid-strokes-only data cannot measure false triggers per 10 minutes, the
  harder TMB-033 criterion, and recall on pre-segmented strokes is weak
  evidence.
- The best realistic payoff is narrow: descriptive forearm-rotation
  morphology (backswing presence, rise-to-peak time) across 12 players. Owner
  data from TMB-030 S4/N4 and Galaxy sessions answers the product question
  directly.

Proceed to Stage 2 only if the owner (1) accepts the CC BY-NC-ND terms for the
intended use and (2) approves the download. Then extract only the minimum
needed (one section `.json`) into a new directory outside the repository,
record the archive SHA-256, answer Section 6, and decide again before writing
an adapter. Reject if the owner expects commercial use or if Section 6 shows
processed or unrecoverable units or timestamps.
