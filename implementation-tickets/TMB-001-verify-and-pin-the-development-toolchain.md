# TMB-001 — Verify and pin the development toolchain

**Status:** Done  
**Labels:** `foundation`  
**Estimate:** 0.5 day  
**Dependencies:** None

### Implementation steps

1. Inventory installed Godot, Xcode, Swift, Android Studio, Android SDK, Kotlin/Gradle, JDK and Git versions.
2. Select one stable version of each tool for the project.
3. Confirm that the physical iPhone and Pixel can be deployed to from this Mac.
4. Create `docs/development.md` with installation, version and device-deployment instructions.
5. Record any required local-network, camera, motion and debug permissions.

### Acceptance criteria

- The selected tool versions are explicitly documented.
- A minimal iOS app runs on the physical iPhone.
- A minimal Android app runs on the physical Pixel.
- A minimal Godot project runs on the development machine.

### Evidence

- `docs/development.md`
- Version command output or screenshots attached to the ticket
- Physical-device launch confirmation for both phones

### Implementation log

- 2026-11-06: Inventoried and pinned the local toolchain in
  `docs/development.md`.
- 2026-11-06: Saved redacted command output in
  `docs/evidence/TMB-001-toolchain.txt`.
- 2026-11-06: Installed Godot 4.7.2 and passed the local headless smoke test.
- 2026-11-06: Automatically signed, installed and launched the controller on a
  physical iPhone 17e with Developer Mode enabled. Device identifiers remain
  redacted from evidence.
- 2026-11-06: Passed all 12 XCTest cases on the physical iPhone after packaging
  the shared protocol vectors as test-bundle resources; Simulator remains green.
- Physical Android launch remains pending until the available Galaxy reference
  device is connected; the originally planned Pixel is unavailable.


