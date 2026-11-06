# iOS motion controller

Native SwiftUI controller shell with the shared controller states, version and
device diagnostics, permission explanations and session-scoped keep-awake
policy.

## Generate and build

The committed Xcode project is generated from `project.yml` using XcodeGen
2.45.4:

```sh
cd apps/controller-ios
xcodegen generate
xcodebuild -project MotionControllerIOS.xcodeproj \
  -scheme MotionControllerIOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 QA' \
  build test
```

`MotionControllerIOS.xcodeproj` is generated and git-ignored. For a physical
build, supply the local development team when generating; `project.yml` reads
it from the environment so the value is never committed:

```sh
DEVELOPMENT_TEAM=<your-team-id> xcodegen generate
```

Without it, simulator builds and tests work unchanged. Signing and provisioning
values must remain local and must not be committed.
