# TMB-005 — Create the iOS controller application shell

**Status:** Done  
**Labels:** `foundation`, `controller-ios`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-002

### Implementation steps

1. Create the Swift application in `apps/controller-ios`.
2. Add screens/states for Not Paired, Pairing, Calibration, Connected and Paused.
3. Add application version and device information to a debug panel.
4. Declare camera, motion and local-network permission messages.
5. Add a keep-awake policy that activates only during an active session.

### Acceptance criteria

- The application installs and opens on the target iPhone.
- Each placeholder state can be reached through a debug control.
- Permission explanations are user-readable and specific.
- Keep-awake is disabled when no session is active.

### Evidence

- Physical-device screenshots
- App version shown on device

### Implementation log

- 2026-11-06: Added the SwiftUI controller shell, all five shared states,
  version/device diagnostics, permission descriptions and active-session-only
  idle-timer policy.
- 2026-11-06: Passed three state/keep-awake tests and launched version 0.1.0 (1)
  on the iPhone 17 simulator; screenshot saved under `docs/evidence`.
- Physical iPhone installation and screenshots are deferred by explicit project
  owner direction until hardware is available.


