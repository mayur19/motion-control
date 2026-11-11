# AGENTS.md — Two-Phone Motion Badminton

Checkpoint and working rules for coding agents (Codex, Claude Code). Read this
first, then `git log`, `git status` and the ticket you are working on.
Last checkpoint: 2026-11-06, written after `7836d3c` (TMB-029 done; TMB-030 capture in progress).

## Project

Two phones act as motion controllers (badminton rackets) for a desktop game
host. Phones stream IMU samples over UDP on the LAN; the host pairs them by QR,
synchronizes clocks and (later) detects swings and runs the match.

| Path | What |
| --- | --- |
| `Two-Phone Motion Badminton PRD.md`, `...Architecture and Delivery Plan.md` | Product and plan |
| `implementation-tickets/TMB-0NN-*.md` | Tickets with status, acceptance criteria and **implementation log**; `README.md` indexes them |
| `protocol/spec.md`, `protocol/golden-vectors/` | Binary protocol v1 and cross-language fixtures |
| `apps/host-godot/` | Godot 4.7 host (GDScript): ingest, pairing, clock sync, reconnect, HUD, logging |
| `apps/controller-ios/` | SwiftUI/CoreMotion controller (XcodeGen `project.yml`) |
| `apps/controller-android/` | Kotlin controller (AGP 9 built-in Kotlin) |
| `tools/` | Python/Ruby analysis tools with pytest suites |
| `docs/` | Guides (`development.md`, `reconnect.md`, `log-schema.md`, `racket-coordinate-system.md`, …), `test-plans/`, `evidence/` |

## Hard rules

- **Never print or commit** live QR pairing secrets, UDIDs, ECIDs, serial
  numbers or the Apple team ID. Filter all `xcrun devicectl`, `xcodebuild -destination id=…`
  and `adb` output: redact UUID-form IDs, `ecid_[0-9]+` and adb serials.
  Host screenshots show the pairing code, so do not open or commit them.
- **Never commit BadminSense (`BADS_CLL`) data** or anything derived from it
  (section JSON, stroke GIFs, per-stroke values, plots of it). Its CC BY-NC-ND
  license conflicts with this public MIT repo. Keep the archive outside the
  repo (or in git-ignored `external-data/`); docs may hold only aggregate prose
  findings. `tools/test_no_external_data.py` enforces this.
- The Xcode project is generated and git-ignored. Device builds:
  `DEVELOPMENT_TEAM=<team> xcodegen generate` (the value lives only in the
  developer's environment).
- Preserve others' work: inspect `git status`/`git log` before editing; never
  reset, discard or overwrite uncommitted changes you did not make.
- Tests first (write the failing test, then the fix). Evidence must be honest:
  never present automated or estimated results as physical measurements; record
  gaps and owner decisions explicitly in the ticket implementation log.
- Commits: conventional (`feat:`, `fix:`, `docs:`, `chore:` …), no AI attribution
  lines. Remote: `origin` = public `github.com/mayur19/motion-control` (MIT), branch `main`.

## Commands

```sh
# Host (Godot): every tests/*_test.gd prints TMB-..._OK and exits 0
godot --headless --path apps/host-godot --import
for t in apps/host-godot/tests/*_test.gd; do
  godot --headless --path apps/host-godot --script "res://tests/$(basename "$t")" -- --output="$TMPDIR/$(basename "$t" .gd).jsonl"
done
godot --headless --path apps/host-godot -- --smoke-test        # TMB-004_HOST_SMOKE_OK
godot --path apps/host-godot -- --print-session --session-log-max-mb=128   # visible host
#   options: --reconnect-window-s=N (5-60, default 30), --latency-test (F4 toggles stimulus),
#            --log-normalized-motion (raw vs normalized records; F5 shows the live plot)

# iOS (simulator)
cd apps/controller-ios && xcodegen generate && xcodebuild -project MotionControllerIOS.xcodeproj \
  -scheme MotionControllerIOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 QA' build test

# Android
cd apps/controller-android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ANDROID_HOME=$HOME/Library/Android/sdk
./gradlew testDebugUnitTest assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk

# Capture (host F6 panel) and offline replay (TMB-029; docs/capture-format.md)
godot --headless --path apps/host-godot --script res://replay/replay_capture.gd -- --capture=DIR --output=result.json
python3 -I tools/capture-labels.py {list|verify|correct --take N --set field=value} DIR

# Tools
python3 -m pytest -q tools/
python3 -I tools/check-reconnect-log.py <session.jsonl>          # TMB-021 physical reconnect checks
python3 -I tools/soak-report.py <session.jsonl> <start_s> [end_s] # TMB-022 thresholds
python3 -I tools/latency-frames.py VIDEO --capture-fps 240 --marker X,Y,W,H --display X,Y,W,H
```

Host session logs (JSONL) are written to
`~/Library/Application Support/Godot/app_userdata/Motion Badminton Host/logs/`.
Ask the operator to **close the host window** (a clean close flushes the log);
killing it truncates the last line.

## Physical devices and environment

- iPhone 17e: the owner's phone, usually on USB. If `xcodebuild` cannot find
  it, it is locked or asleep; ask the user to unlock it.
- Samsung Galaxy M14 5G (SM-M146B, Android 15). It is borrowed and only
  intermittently available, so ask before planning Android physical steps. No
  Pixel.
- Host: Mac14,9 (M2 Pro), **Wi-Fi only** (no Ethernet), 5 GHz channel 48.
  **macOS AWDL** (AirDrop/Continuity) adds about 100 ms input delay every
  0.52 s on a Wi-Fi host. The host warns on the pairing panel and logs
  `awdl_state`. For measurements: `sudo ifconfig awdl0 down` (undo: `up`).
- QR codes expire after 120 s. Use **NEW PAIRING CODE** (this rotates the
  session, so every phone must rescan). The default disconnect reservation is
  30 s; phones retry a rejoin for 60 s.
- Keep human-in-the-loop tests short (minutes); the owner has said 10-minute
  sessions are too long.

## State at checkpoint

Done and physically verified (ticket logs, `docs/evidence/`):

- TMB-001–023: protocol, controllers, host ingest, pairing, clock sync,
  reconnect, soak (both phones pass with Wi-Fi host and AWDL off).
- TMB-025 Gate A: final `GO` (owner decision with an evidence exception).
- TMB-026 common racket frame (`docs/racket-coordinate-system.md`). Core Motion
  attitude is device-to-reference and is **not** inverted (ADR-011).
- TMB-027 slow-swing calibration on iPhone and Galaxy, both hands, within the
  owner's physical limits (0.05 m/s², 0.10 rad/s, 5°). Rejoin resends the
  stored calibration; both apps have Recalibrate.
- TMB-028 host calibration gate (`motion/calibration_normalizer.gd`): raw axes
  are kept, `normalized` is attached, and only `normalized_sample_received`
  feeds detection. F5 shows a raw vs normalized plot.
- TMB-029 labeled capture/replay (`docs/capture-format.md`): F6 capture panel,
  immutable `raw.jsonl` + `raw.sha256`, append-only `labels.jsonl`, headless
  replay; live and replay detector events are identical.

In progress / review:

- **TMB-030 dataset (owner-run, In Progress).** Plan:
  `docs/test-plans/tmb-030-dataset-capture-plan.md` (full target chosen: per
  phone 4 swing + 4 non-swing sessions of ≤ 6 min; S4/N4 held out). Done:
  iPhone S1 (34 swings, estimated counts, tune) and N1 (tune). Inventory:
  iPhone 34/100 swings, 5.4/20 non-swing minutes; Galaxy none. Captures and
  `dataset-splits.json` live in the host user-data `captures/` folder
  (not in git). Only the owner can record sessions; never invent labels or
  counts.
- **TMB-031 preprocessing and TMB-032 `early_rise` detector: Review** under an
  owner-approved dependency exception. Thresholds are provisional, and the
  backswing vs forward-swing question needs labeled data
  (`docs/motion-preprocessing.md`, `docs/swing-detection.md`).
- TMB-033 onward are blocked by data; all gameplay waits for the TMB-035 gate.

Open items:

- TMB-022: no Ethernet-host run is possible on this Mac.
- `--latency-test` starts armed, which hides the pairing QR (press F4 twice);
  small host fix pending.
- Android stops background traffic after ~5 s; a foreground service is an
  owner decision.
- A paused controller (invalid calibration) is not told on screen (no
  protocol message). Duplicate samples are dropped by preprocessing.

Hard-won gotchas:

- The protocol is **big-endian**. MOTION gyro sits at datagram bytes 48–59.
- Godot `JSON.stringify` loses precision on 64-bit ints: store session ids as
  decimal strings.
- The GDScript project treats inferred-Variant warnings as errors (use typed
  `var x: T = …`). A `SceneTree` test with a parse error never quits, so run
  tests under `timeout`.
- `--print-session` prints the live pairing secret: don't use it in agent runs.
- zsh does not word-split `$var` in loops.

Next by plan: owner sessions for TMB-030 (iPhone S2/N2 next), TMB-033
evaluation tooling, then onward per `implementation-tickets/README.md`.
