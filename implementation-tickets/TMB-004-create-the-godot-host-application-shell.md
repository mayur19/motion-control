# TMB-004 — Create the Godot host application shell

**Status:** Done  
**Labels:** `foundation`, `host`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-002

### Implementation steps

1. Create the Godot project in `apps/host-godot`.
2. Add a main scene with placeholders for session status, Player 1, Player 2 and diagnostics.
3. Add a build/version label populated from a single project version value.
4. Configure a fixed physics tick independent from rendering.
5. Add a headless launch mode for future automated tests.

### Acceptance criteria

- The host launches without warnings or missing resources.
- Resizing the window does not break the placeholder layout.
- Headless startup exits successfully through a smoke-test path.

### Evidence

- Host screenshot
- Headless smoke-test output

### Implementation log

- 2026-11-06: Added a responsive host shell with session, player and network
  diagnostics placeholders and a project-sourced version label.
- 2026-11-06: Configured a 120 Hz fixed physics tick and headless smoke mode.
- 2026-11-06: Verified editor import, headless launch and 1280×720/800×600
  rendered layouts without missing resources or startup warnings.


