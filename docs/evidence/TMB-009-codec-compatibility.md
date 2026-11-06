# TMB-009 protocol v1 compatibility

Captured: 2026-11-06 (Asia/Kolkata)

| Implementation | Positive decode | Byte-exact encode | Negative rejection | Motion values |
| --- | ---: | ---: | ---: | ---: |
| Swift 6 / iOS | 8/8 | 8/8 | 7/7 | Pass |
| Kotlin 2.2.10 / Android | 8/8 | 8/8 | 7/7 | Pass |
| GDScript / Godot 4.7.2 | 8/8 | 8/8 | 7/7 | Pass |

Floating-point comparisons use the manifest tolerance of `0.00001`. Encoders
must still reproduce the source fixture byte-for-byte.

## Swift

```sh
xcodebuild -project MotionControllerIOS.xcodeproj \
  -scheme MotionControllerIOS \
  -destination 'platform=iOS Simulator,id=<simulator>' test
```

Result: 6 tests passed, 0 failed. Three codec test methods iterate all 15
fixtures; the other three cover the controller state shell.

## Kotlin

```sh
./gradlew testDebugUnitTest --warning-mode=all
```

Result: 6 tests passed, 0 failed. `ProtocolV1FixtureTest` executed 3 methods over
all fixtures; `ControllerStateTest` executed 3 shell-state methods.

## GDScript

```sh
godot --headless --path apps/host-godot \
  --script res://tests/protocol_fixture_test.gd
```

Result:

```text
TMB-009_GDSCRIPT_CODEC_OK positives=8 negatives=7
```

All implementations reject non-finite sensor values before range checks and
reject invalid quaternion magnitudes before accepting a decoded message.
