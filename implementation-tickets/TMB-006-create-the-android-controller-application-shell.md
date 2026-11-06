# TMB-006 — Create the Android controller application shell

**Status:** Done  
**Labels:** `foundation`, `controller-android`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-002

### Implementation steps

1. Create the Kotlin application in `apps/controller-android`.
2. Add the same application states as the iOS controller.
3. Add application version and device information to a debug panel.
4. Declare camera, network and wake-lock requirements.
5. Add a keep-awake policy that activates only during an active session.

### Acceptance criteria

- The application installs and opens on the target Pixel.
- Controller state names and intended transitions match the iOS application.
- Keep-awake is disabled when no session is active.

### Evidence

- Physical-device screenshots
- App version shown on device

### Implementation log

- 2026-11-06: Added the native Kotlin controller shell with the same five state
  names/order as iOS, version/device diagnostics and required permissions.
- 2026-11-06: Added an active-session-only `FLAG_KEEP_SCREEN_ON` policy that is
  cleared on pause or focus loss.
- 2026-11-06: Passed three unit tests, built the APK without warnings, launched
  version 0.1.0 (1) on the Pixel emulator and exercised all five states.
- Physical Pixel installation and screenshots are deferred by explicit project
  owner direction until hardware is available.


