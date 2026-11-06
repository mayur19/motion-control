# TMB-026 — Define the common racket coordinate system

**Status:** Ready — Gate A provisional `GO` (2026-11-06); the work is revisited if Gate A is revoked  
**Labels:** `detection`, `protocol`, `architecture`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-025 (`GO`)

### Implementation steps

1. Define phone grip orientation and common racket X/Y/Z axes.
2. Define left-handed and right-handed transforms.
3. Define neutral orientation and acceptable calibration range.
4. Add diagrams and numeric examples.

### Acceptance criteria

- The same physical motion has the same sign and axis meaning on both phones.
- Handedness does not require separate gameplay logic.
- The definition is precise enough for automated fixture tests.

### Evidence

- `docs/racket-coordinate-system.md`


