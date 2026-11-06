# AGENTS.md — Two-Phone Motion Badminton

Checkpoint and working rules for coding agents (Codex, Claude Code). Read this
first, then `git log`, `git status` and the ticket you are working on.
Last checkpoint: 2026-11-06, written after `4694d18` (TMB-026 done).

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
- The Xcode project is generated and git-ignored. Device builds:
  `DEVELOPMENT_TEAM=<team> xcodegen generate` (the value lives only in the
  developer's environment).
- Preserve others' work: inspect `git status`/`git log` before editing; never
  reset, discard or overwrite uncommitted changes you did not make.
- Tests first (write the failing test, then the fix). Evidence must be honest:
  never present automated or estimated results as physical measurements; record
  gaps and owner decisions explicitly in the ticket implementation log.
- Commits: conventional (`feat:`, `fix:`, `docs:`, `chore:` …), no AI attribution
  lines. Remote: `origin` = private `github.com/mayur19/motion-control`, branch `main`.

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

Done and physically verified (see the ticket logs and `docs/evidence/`):
TMB-001 to TMB-023 implemented. TMB-019/020/021 pairing, clock sync, reconnect
and host-loss pass on iPhone and Galaxy. TMB-022 soak, Wi-Fi host, AWDL off:
both phones pass (0.12% / 0.17% loss + late). **Gate A (TMB-025) has a final
`GO`** (owner decision, accepted evidence exception; see the TMB-025 decision
record). **TMB-026** (common racket coordinate frame) is done at `4694d18`.

**TMB-027** (slow-swing calibration) is Done: physically verified on iPhone
and Galaxy, both hands, within the owner's physical repeatability limits
(0.05 m/s² accel bias, 0.10 rad/s gyro bias, 5° tilt). The iPhone run fixed a
TMB-026 defect: Core Motion attitude is already device-to-reference and is no
longer inverted. Rejoin resends the stored calibration. See
`docs/evidence/TMB-027-calibration.txt`. Not pushed.

Open items (not blocking M2 unless noted):
- TMB-022: an Ethernet-host run is impossible on this Mac; the AWDL-off run
  lasted 198 s of the agreed 5 minutes.
- Galaxy needs an on-device check of the debug-panel wrap fix (the latest build
  is installed).
- `--latency-test` starts with the stimulus armed, which hides the pairing QR
  (press F4 to pair, then F4 again). Plan text says F4 arms it; small host fix
  pending.
- Android stops background network traffic after about 5 s; a background
  longer than about 17 s returns as a new player. A foreground service is an
  owner decision.
- The Galaxy once failed to receive WELCOME (not reproducible); join debug
  logging (tag `MotionBadminton`) is in place.
- The PRD's thresholds for rate and frame stall were set by the owner for
  TMB-022: median >= 99 Hz, no frame > 150 ms, frame p99 < 50 ms.

TMB-028 host calibration is Done (`docs/evidence/TMB-028-host-calibration.txt`).
TMB-029 capture/replay is Done (`docs/evidence/TMB-029-capture-replay.txt`).
TMB-030 baseline dataset: In Progress. Plan in
`docs/test-plans/tmb-030-dataset-capture-plan.md`; captures + `dataset-splits.json`
live in the host user-data `captures/` folder; report with
`python3 -I tools/dataset-inventory.py <captures dir> --markdown out.md`.
TMB-031 preprocessing and TMB-032 early-rise detector: Review under an
owner-approved dependency exception (provisional thresholds; tuning and the
backswing question wait for TMB-030 data). Docs: `docs/motion-preprocessing.md`,
`docs/swing-detection.md`.
Then onward per
`implementation-tickets/README.md`.
