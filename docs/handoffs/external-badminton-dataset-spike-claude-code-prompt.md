# Claude Code handoff — external badminton dataset spike

Continue development in `~/IdeaProjects/motion-control` on branch
`main`. Read, in order:

1. `AGENTS.md`, then `git log --oneline -15` and `git status`.
2. `implementation-tickets/TMB-030-capture-the-baseline-motion-dataset.md`.
3. `implementation-tickets/TMB-032-implement-the-early-swing-detector.md`.
4. `implementation-tickets/TMB-033-build-detector-evaluation-and-tuning-reports.md`.
5. `docs/capture-format.md`, `docs/motion-preprocessing.md`,
   `docs/swing-detection.md` and `docs/detector-evaluation.md`.

Do not discard uncommitted work, print pairing/device secrets, push, download a
large dataset, or run physical-device steps without the owner's approval.

## Owner decision and purpose

The owner wants to use public badminton datasets where they add evidence. They
are **supplementary, off-domain datasets**, not replacements for TMB-030 and
not part of the product tune/held-out split. Start with a narrowly scoped
BadminSense/BADS_CLL applicability spike under TMB-033; do not open another
implementation ticket, because TMB-030 and TMB-033 are already in progress.

The first question is not “how high is detector recall on 848 more swings?” It
is whether the published sensor stream can be interpreted honestly enough to
run a meaningful external robustness check. The source is a smartwatch on the
wrist, while this product uses a phone gripped as the racket handle. Its axes,
units, placement, calibration, sampling behavior and labels are a different
domain.

Official source:

- <https://github.com/taizhouchen/BadminSense_Dataset>
- The repository describes 848 valid strokes with accelerometer, gyroscope,
  magnetometer, audio and video data across four stroke labels.
- The download is approximately 14 GB and is licensed CC BY-NC-ND 4.0.

The owner has not yet approved the 14 GB download or decided that the
non-commercial/no-derivatives terms fit the intended product. Ask before the
download. Never commit source data, derived samples from it, video or audio.

## Stage 1 — repository-only applicability work

This stage must not require the dataset download.

1. Add `docs/external-dataset-evaluation.md` covering:
   - the question each public dataset can and cannot answer;
   - BadminSense sensor placement, published fields, labels and license;
   - the domain gaps versus iPhone/Pixel held as a racket controller;
   - a strict separation between `internal tune`, `internal heldout` and
     `external/off-domain` results;
   - why pre-segmented valid strokes cannot establish idle/handling false
     triggers per 10 minutes;
   - the minimum metadata that must be confirmed from a real sample before an
     adapter is implemented: timestamp units, sample rate/jitter, sensor units,
     coordinate convention, calibration status, segment boundaries and
     missing/duplicate samples.
2. Add an implementation note to the TMB-033 log. State that this is an
   external-data applicability spike and that no physical/product performance
   claim can be made from it.
3. If useful, add a small machine-readable source manifest under `tools/` or
   `docs/` containing source URL, version, license, expected modalities and
   placement. Do not mirror dataset content.

Keep Stage 1 documentation-focused. Do not invent an axis transform, assume
that smartwatch axes equal the common racket frame, or feed fabricated values
into `DetectorPipeline`.

## Stage 2 — only after owner approval and a real schema sample

After approval, inspect the minimum real sample needed to resolve the metadata
questions above before downloading or processing the whole corpus. Record the
dataset version and an integrity hash for every local source archive, but keep
all source data outside Git.

Then use tests-first development for a read-only BadminSense adapter under
`tools/`:

- parse the published JSON without changing source files;
- expose timestamps, accelerometer and gyroscope values, stroke label and
  participant/section identifiers;
- preserve the original values and units in adapter output;
- fail on unknown units, malformed timestamps and missing required streams;
- use a hand-authored synthetic fixture in pytest, not copied dataset content;
- initially compute placement-robust descriptive signals such as angular-speed
  magnitude and duration distributions;
- do not force the data through phone calibration or claim direct threshold
  comparability until an explicit, evidence-backed mapping exists.

Only if the schema and units support it, add an external evaluation mode. Its
reports must:

- be labeled `external/off-domain` prominently;
- save the source dataset/version, adapter version and exact detector and
  preprocessing configuration;
- report results separately from TMB-030 tune and held-out reports;
- never influence the frozen internal held-out evaluation;
- explain that isolated valid strokes can test sensitivity/morphology but not
  continuous-use precision or false triggers per 10 minutes;
- avoid using BadminSense stroke-quality ratings as product ground truth.

## Other public datasets

Record these as later candidates, not current detector inputs:

- MultiSenseBadminton: wearable biomechanics across players, but not a
  phone/racket-handle stream; potentially useful for later shot intent.
  <https://github.com/dailyminiii/MultiSenseBadminton>
- ShuttleSet: tactical match annotations, no controller IMU.
  <https://github.com/wywyWang/CoachAI-Projects/tree/main/ShuttleSet>
- BFMD: broadcast video, pose, shuttle trajectories and shot labels.
  <https://ning-d.github.io/BFMD-Dataset/>
- Mendeley frame-level motion dataset: video/frames, not IMU.
  <https://data.mendeley.com/datasets/3sp4xntp34/1>
- VideoBadminton: fine-grained video action recognition, not IMU.
  <https://github.com/qilimk/VideoBadminton>

These may help TMB-034 or later gameplay/shot-taxonomy work, but they cannot
validate TMB-032 trigger thresholds.

## Definition of done for the initial spike

- Stage 1 documentation is committed with primary-source links and the
  TMB-033 implementation log is updated.
- The document ends with a clear recommendation: proceed with a minimal sample
  inspection, defer, or reject, including the license and technical reasons.
- No public data has been committed and no internal held-out session has been
  evaluated or exposed.
- Run `git diff --check` and `python3 -m pytest -q tools/`. If code or Godot
  files are changed, follow the complete `AGENTS.md` test matrix.
- Use a focused conventional commit and do not push.
- Report what is documented or synthetically verified separately from what
  remains pending on real external data and owner approval.

