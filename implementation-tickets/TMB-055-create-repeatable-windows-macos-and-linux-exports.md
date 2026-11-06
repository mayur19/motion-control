# TMB-055 — Create repeatable Windows, macOS and Linux exports

**Status:** Blocked — Gate B has no `GO` decision  
**Labels:** `release`, `host`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-054 (`GO`)

### Implementation steps

1. Add Godot export presets for Windows, macOS and Linux.
2. Define version naming and artifact layout.
3. Ensure debug HUD/logging defaults are appropriate for test releases.
4. Record platform-specific networking/firewall prompts.
5. Build all three artifacts from a clean checkout or CI environment.

### Acceptance criteria

- All artifacts share the same game/protocol version.
- No Windows-only API or path is required.
- Each artifact launches to the host setup screen.

### Evidence

- Export logs and artifact checksums


