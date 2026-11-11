# Getting started

This guide takes you from a fresh clone to a phone streaming motion into the
host. Exact tool versions are pinned in [development.md](development.md); use
those when something does not build.

> The game itself is not built yet. Today the host is a motion laboratory:
> you can pair phones, watch live motion and diagnostics, calibrate, record
> labeled captures and run the swing detector.

## 1. What you need

| For | Requirement |
| --- | --- |
| Host | macOS (tested), Windows or Linux; [Godot 4.7.2](https://godotengine.org/) standard (non-.NET) build on `PATH` as `godot` |
| iOS controller | Mac with Xcode 26.4, [XcodeGen](https://github.com/yonaskolb/XcodeGen), an iPhone (iOS 26) for physical use |
| Android controller | Android Studio, Android SDK API 36, JDK 17, an Android phone with gyroscope and rotation-vector sensors |
| Tools | Python 3 with `pytest`; Ruby for the packet generator and clock plot |
| Network | One Wi-Fi network shared by host and phones, preferably 5 GHz, **without client isolation** (guest networks usually isolate) |
| Safety | A wrist strap or tether for each phone and clear space around you |

## 2. Run the host

```sh
godot --headless --path apps/host-godot --import            # first run: import assets
godot --headless --path apps/host-godot -- --smoke-test     # expect TMB-004_HOST_SMOKE_OK
godot --path apps/host-godot                                 # visible host
```

Arguments after the second `--` belong to the app, not to Godot. The host
shows a pairing panel with a QR code, a manual code, and the selected LAN
address and port. If the computer has several network interfaces (VPN,
Docker, etc.), choose the address on the same network as the phones.

### macOS: turn off AWDL

AirDrop, Handoff and other Continuity features use AWDL, which stalls Wi-Fi
receive for about 100 ms every half second. The host warns when it is active.
For clean results:

```sh
sudo ifconfig awdl0 down    # undo with: sudo ifconfig awdl0 up
```

An Ethernet-connected host avoids the problem entirely.

## 3. Build and install a controller

### iOS

```sh
cd apps/controller-ios
xcodegen generate
# Simulator build and tests (pick any installed iPhone simulator name)
xcodebuild -project MotionControllerIOS.xcodeproj -scheme MotionControllerIOS \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build test
```

For a physical iPhone, generate the project with your own signing team; the
value comes from your environment and is never committed:

```sh
DEVELOPMENT_TEAM=<your-team-id> xcodegen generate
open MotionControllerIOS.xcodeproj    # select your iPhone and Run
```

The simulator has no motion sensors, so streaming needs a real device.

### Android

```sh
cd apps/controller-android
export JAVA_HOME=<path to JDK 17>           # Homebrew: /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
./gradlew testDebugUnitTest assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Keep the app in the foreground while playing; Android currently stops
background traffic after about 5 seconds.

## 4. Pair, calibrate, stream

1. Start the host. A QR code is valid for **120 seconds**; press
   **NEW PAIRING CODE** for a fresh one (this starts a new session, so every
   phone must scan again).
2. Open the controller app and scan the QR code, or type the manual code.
3. Confirm the strap is on and the space is clear.
4. Calibrate: hold the phone as a racket handle (portrait, top edge pointing
   toward the racket head, screen facing you, wrist straight), choose your
   hand, keep still for the neutral capture, then make one **slow, controlled**
   swing.
5. The host shows the phone as Player 1 or 2 with live rate, loss, jitter,
   sample age and RTT. Move the phone and watch the graph.

A phone that drops out keeps its seat for 30 seconds (configurable with
`--reconnect-window-s=5..60`) and rejoins automatically with its stored
calibration. Use **Recalibrate** in the app to redo calibration.

## 5. Host keys and options

| Key / option | Effect |
| --- | --- |
| **F4** / `--latency-test` | Latency stimulus: full-screen flash on a raw gyro threshold; `[` and `]` adjust the threshold. The mode starts armed and hides the QR, so press F4 twice to pair |
| **F5** / `--log-normalized-motion` | Live raw vs calibrated plot; logs both |
| **F6** | Capture panel for labeled takes (see [capture format](capture-format.md)) |
| `--session-log-max-mb=N` | Session log size cap |
| `--reconnect-window-s=N` | Seat reservation after disconnect, 5–60 s |

Avoid `--print-session` when sharing your screen or logs: it prints the live
pairing secret.

## 6. Logs, captures and replay

- Session logs (JSONL): `~/Library/Application Support/Godot/app_userdata/Motion Badminton Host/logs/`
  on macOS (Godot's `user://logs` elsewhere). Close the host window normally so
  the last line is flushed.
- Captures: `user://captures/<capture_id>/` with `raw.jsonl`, `raw.sha256` and
  `labels.jsonl`.

```sh
# Replay a capture through the live detector pipeline, headless
godot --headless --path apps/host-godot --script res://replay/replay_capture.gd -- \
  --capture=DIR --output=result.json

# Inspect or correct labels (corrections append revisions; raw data never changes)
python3 -I tools/capture-labels.py list DIR
python3 -I tools/capture-labels.py verify DIR

# Network health for a window of a session log
python3 -I tools/soak-report.py SESSION.jsonl START_S [END_S]
```

## 7. Run all tests

```sh
# Host: every tests/*_test.gd prints TMB-…_OK and exits 0.
# Use a timeout: a SceneTree test with a parse error never quits.
for t in apps/host-godot/tests/*_test.gd; do
  name=$(basename "$t" .gd)
  timeout 120 godot --headless --path apps/host-godot --script "res://tests/$name.gd" \
    -- --output="${TMPDIR:-/tmp}/$name.jsonl" || echo "FAILED: $name"
done

python3 -m pytest -q tools/                         # tools
(cd apps/controller-android && ./gradlew testDebugUnitTest)
(cd apps/controller-ios && xcodegen generate && xcodebuild -project MotionControllerIOS.xcodeproj \
  -scheme MotionControllerIOS -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' test)
```

On macOS, `timeout` comes from GNU coreutils (`brew install coreutils`, then
`gtimeout` or add it to `PATH`).

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| QR scans but the phone never connects | Client isolation on the Wi-Fi, a firewall, or the host advertised a VPN/virtual address | Use a private network or hotspot; allow Godot through the firewall; pick the correct LAN address on the pairing panel |
| "Expired" when scanning | QR older than 120 s | Press NEW PAIRING CODE |
| Regular bursts of late samples (~every 0.5 s) on a Mac | AWDL | `sudo ifconfig awdl0 down` or turn off AirDrop/Handoff |
| Android phone drops after a few seconds | App left the foreground or the screen turned off | Keep the app open and the screen on |
| Samples appear far in the future (Android) | Mixed timestamp time bases | Fixed in current builds; update the app |
| Calibration keeps failing | Phone moved during neutral capture, wrong grip, or swing too fast | Hold still, check the grip, swing slowly |
| No detector triggers for a phone | Phone not calibrated for the current session (uncalibrated samples never reach detection) | Recalibrate; rotating the session drops calibrations |
| Host log's last line is truncated | Host was killed | Close the window normally |
| A Godot test hangs | Parse error in a `SceneTree` test | Run under `timeout`; typed variables are required (inferred-Variant warnings are errors) |
