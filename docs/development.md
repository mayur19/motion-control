# Development environment

This document defines the supported local toolchain for Two-Phone Motion
Badminton. Use the exact versions below until a deliberate upgrade updates this
file and the affected build files together.

## Pinned toolchain

| Area | Pinned version | Local verification |
| --- | --- | --- |
| Godot | 4.7.2 stable, standard build (GDScript) | `godot --version` |
| Xcode | 26.4.1 (17E202) | `xcodebuild -version` |
| Swift | 6.3.1 | `swift --version` |
| iOS SDK | 26.4 | `xcodebuild -showsdks` |
| Android Studio | 2026.1.1, build AI-261.23567.138.2611.15646644 | About dialog or `product-info.json` |
| Android compile/target SDK | API 36 (Android 16) | `sdkmanager --list_installed` |
| Android SDK Build Tools | 36.0.0 | `sdkmanager --list_installed` |
| Android SDK Platform Tools | 37.0.0 | `adb version` and `source.properties` |
| Android Gradle Plugin | 9.2.1 | Root Android build file (from TMB-006) |
| Gradle | 9.4.1, via project wrapper | `./gradlew --version` (from TMB-006) |
| Kotlin | 2.2.10, provided by AGP built-in Kotlin | `./gradlew buildEnvironment` |
| JDK for Android builds | OpenJDK 17.0.18 | See Android JDK setup below |
| Git | 2.50.1 (Apple Git-155) | `git --version` |

The pins use stable releases, not preview or beta builds. Godot 4.7.2 is the
latest stable Godot 4 release available when this file was written. Xcode and
Android Studio are pinned to the installed stable builds. Android Gradle Plugin
9.2.1 and Gradle 9.4.1 are a documented compatible pair. The project uses AGP
9's built-in Kotlin support and its pinned Kotlin Gradle Plugin 2.2.10 runtime,
avoiding a second, potentially conflicting `kotlin-android` plugin declaration.

The Android Studio IDE runs on its bundled JBR 21. The project build uses JDK 17
because it is the Android Gradle Plugin 9.2 default and is already installed.
Do not use the machine-wide JDK 22 for this project.

## Install and select the tools

### Godot

Install the standard (non-.NET) editor:

```sh
brew install --cask godot
godot --version
```

The expected version prefix is `4.7.2.stable`.

### Xcode and Swift

Install Xcode 26.4.1, open it once to complete first-launch setup, and select it:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
xcodebuild -version
swift --version
```

Signing requires an Apple ID in **Xcode > Settings > Accounts**. Select a
development team on the iOS target; keep signing identities and provisioning
profiles out of Git.

### Android Studio, SDK and JDK

Install Android Studio 2026.1.1. In **Settings > Languages & Frameworks > Android
SDK**, install API 36, Build Tools 36.0.0, Platform Tools 37.0.0 and Command-line
Tools 20.0.

The equivalent command-line check is:

```sh
$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager --list_installed
```

Set the Gradle JVM in Android Studio to the installed JDK 17, or export it for a
terminal build:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
./gradlew --version
```

Gradle and Kotlin are project dependencies. Do not install or rely on a global
`gradle` or `kotlinc`; the Android project created by TMB-006 will carry the
pins and the Gradle wrapper.

## Physical iPhone deployment

1. Connect the iPhone 17e by USB, unlock it and choose **Trust This Computer**.
2. Enable **Settings > Privacy & Security > Developer Mode**, then restart and
   confirm Developer Mode when prompted.
3. Open the iOS project in Xcode, select the phone as the run destination, and
   select the developer team under **Signing & Capabilities**.
4. Run the app. If iOS reports an untrusted developer, approve the developer
   app in **Settings > General > VPN & Device Management** and run again.
5. Confirm the device is available from the terminal:

   ```sh
   xcrun xctrace list devices
   xcrun devicectl list devices
   ```

For the TMB-001 acceptance check, record the date, app build, device model and a
successful foreground launch in the evidence file. Do not commit the device
UDID.

## Physical Pixel deployment

1. On the Pixel 10 Pro, enable **Developer options** by tapping **Build number**
   seven times.
2. Enable **USB debugging**, connect the phone by USB, choose file transfer if
   prompted, and approve the computer's RSA key.
3. Confirm that `adb devices -l` reports the phone as `device`, not
   `unauthorized` or `offline`.
4. Select the Pixel as the Android Studio run target and run the debug build.

For the TMB-001 acceptance check, record the date, app build, device model and a
successful foreground launch in the evidence file. Do not commit the ADB serial
number.

## Application permissions

Keep permission requests close to the feature that needs them and include a
plain-language explanation in the UI.

### iOS controller

- `NSCameraUsageDescription`: scan the host session QR code.
- `NSMotionUsageDescription`: read device motion for racket tracking.
- `NSLocalNetworkUsageDescription`: exchange controller packets with the host
  on the player's local network.
- Development signing, a trusted developer certificate and Developer Mode are
  required for debug deployment but are not application permissions.
- Bonjour service declarations are not required while QR payloads provide the
  host address directly. Add them only if Bonjour discovery is introduced.

### Android controller

- `android.permission.INTERNET`: send and receive local-network packets.
- `android.permission.CAMERA`: scan the session QR code; request it at runtime.
- `android.permission.HIGH_SAMPLING_RATE_SENSORS`: sample motion sensors above
  200 Hz when the device supports it.
- `android.permission.WAKE_LOCK`: hold the Wi-Fi/performance lock during an
  active controller session.
- Accelerometer and gyroscope access does not require `BODY_SENSORS`.
- USB debugging and the host RSA authorization are required only for debug
  deployment.

## Local network checklist

- Put the host and phones on the same non-guest Wi-Fi network.
- Disable client isolation and VPN routing for the first connectivity test.
- Keep each controller app in the foreground during latency measurements.
- Allow the Godot host through the desktop firewall for private/local networks.
- Use an unprivileged UDP port and never commit pairing secrets or captured
  session payloads.

### macOS host: AirDrop/Continuity (AWDL)

On a Mac hosting over **Wi-Fi**, AWDL (Apple Wireless Direct Link, used by
AirDrop, AirPlay, Handoff, Sidecar and Universal Control) periodically takes the
Wi-Fi radio off-channel. In the TMB-022 soak this delayed about 23% of
controller samples by about 100 ms every 0.52 s; with AWDL off, late samples
fell to about 0.15% and sample-age p95 to about 20 ms. The host shows a warning
on the pairing panel while AWDL is active and logs each change as an
`awdl_state` event.

Preferred: connect the host Mac by **Ethernet** (AWDL then cannot delay LAN
input). Otherwise, before a session:

1. Control Centre > AirDrop > **No One**.
2. System Settings > General > AirDrop & Handoff > turn **Handoff** off, and
   avoid AirPlay or Sidecar to or from this Mac.
3. If the host warning stays, the interface is still active. Turn it off
   until the next reboot with:

   ```sh
   sudo ifconfig awdl0 down     # restore with: sudo ifconfig awdl0 up
   ```

   macOS may re-enable it when AirDrop or Continuity is used; the host warning
   reappears if it does.

Steps 1-2 reduce AWDL use but may not stop the interface; the host warning
(which reads `ifconfig awdl0` status) is the source of truth.

## TMB-001 smoke checks

Run these checks after installation:

```sh
godot --version
xcodebuild -version
swift --version
adb version
adb devices -l
/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java -version
git --version
```

The redacted baseline output is stored in
`docs/evidence/TMB-001-toolchain.txt`.

## Project conventions

### Naming

- Use `kebab-case` for repository directories, Markdown files and command-line
  tools.
- Use the platform's conventional type naming: `PascalCase` for Swift/Kotlin
  types and GDScript classes, and `camelCase` for Swift/Kotlin members.
- Use `snake_case` for GDScript files, functions, variables and node groups.
- Use `SCREAMING_SNAKE_CASE` for protocol constants in specifications and map
  them idiomatically in each language.
- Keep protocol message and field names identical across the specification,
  fixtures and codec tests.

### Formatting and generated files

- Use UTF-8, LF line endings and a final newline for text files.
- Use four spaces for Markdown continuation indentation and tabs where Godot's
  GDScript formatter requires them.
- Use `swift-format` for Swift, `ktlint` for Kotlin and Godot's built-in script
  formatter for GDScript once their project configurations are added.
- Never hand-edit generated build products or commit local signing material,
  provisioning profiles, SDK paths or device identifiers.
- Prefer small modules with explicit platform boundaries; protocol and gameplay
  behavior must not depend on a UI framework.

### Commits

Use an imperative subject with one of these prefixes:

- `feat:` user-visible behavior
- `fix:` defect correction
- `test:` automated or manual-test assets
- `docs:` documentation only
- `build:` build system or dependency changes
- `refactor:` behavior-preserving code changes
- `chore:` repository maintenance

Keep each commit focused, include the ticket ID in the body when useful, and do
not mix generated output or unrelated formatting with functional work. Protocol
format changes must include specification, fixtures and all affected tests in
the same reviewable change.
