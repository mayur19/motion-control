# Claude Code handoff — continue TMB-027

Use this prompt verbatim in Claude Code:

```text
Continue TMB-027 in ~/IdeaProjects/motion-control from the latest
commit. Read AGENTS.md, implementation-tickets/TMB-027-implement-slow-swing-
calibration-on-both-controllers.md, docs/racket-coordinate-system.md,
docs/adr/ADR-010-carry-handedness-in-calibration.md, and
docs/evidence/TMB-027-calibration.txt before editing.

The previous agent implemented the Swift/Kotlin calibration validators, iOS
and Android calibration UI flows, one-shot CALIBRATION sending, handedness in
protocol v1 byte 53, regenerated fixtures, and initial host calibration ingest
plus common-frame application. Android unit tests passed. Do not discard or
rewrite this work.

First inspect `git status`, `git show --stat HEAD`, and the checkpoint evidence.
Then finish the verification/fix loop:

1. Run iOS tests:
   cd apps/controller-ios
   xcodebuild test -project MotionControllerIOS.xcodeproj \
     -scheme MotionControllerIOS \
     -destination 'platform=iOS Simulator,name=iPhone 17 QA' \
     CODE_SIGNING_ALLOWED=NO
2. Run Android tests and assemble:
   cd apps/controller-android
   ANDROID_HOME=$HOME/Library/Android/sdk \
     ./gradlew testDebugUnitTest assembleDebug --no-daemon
3. Run protocol fixture check:
   ruby protocol/golden-vectors/generate.rb --check
4. Run Godot tests:
   godot --headless --path apps/host-godot \
     --script res://tests/protocol_fixture_test.gd
   godot --headless --path apps/host-godot \
     --script res://tests/racket_frame_test.gd
   godot --headless --path apps/host-godot \
     --script res://tests/calibration_ingest_test.gd
5. Inspect and fix compiler/parser/test failures. Pay special attention to:
   - Swift concurrency in MotionRuntime calibration task;
   - Android MainActivity programmatic calibration panel behavior;
   - GDScript typed lambdas and Dictionary property access;
   - whether host ingest should apply common-frame transforms here or leave
     more of that work to TMB-028. Keep raw packet logging unchanged.
6. Add final command outputs and results to docs/evidence/TMB-027-calibration.txt.
7. If all acceptance criteria have automated evidence, set TMB-027 to Done and
   TMB-028 to Ready. Otherwise keep TMB-027 Review and state the exact gap.
8. Commit the fixes with a focused message. Leave a clean worktree and report
   commit hash, test results, and any physical-device verification still needed.

Important decisions/context:
- User declared the iPhone and Android latency behavior equivalent and final;
  do not reopen Gate A or request another video.
- TMB-026 is commit 4694d18; final Gate A is c013210.
- ADR-010 intentionally assigns CALIBRATION byte 53 to required handedness
  without changing the 56-byte packet or version because Release 1 is unshipped
  and all three codecs/fixtures changed atomically.
- Neutral limits are normative in docs/racket-coordinate-system.md. Slow swing:
  600 ms–3 s, >=50 samples and >=100 Hz, 20°–140° excursion, 0.6–5 rad/s peak.
- Calibration must explicitly warn: slow practice swing, no full force.
```

## Checkpoint inventory

- Last completed commits before TMB-027: `c013210` (final Gate A GO), `4694d18`
  (TMB-026 coordinate frame).
- Android tests passed at checkpoint.
- iOS simulator suite passed 27/27.
- New Godot calibration-ingest test passed.
- Ticket remains Review until those checks are closed.
