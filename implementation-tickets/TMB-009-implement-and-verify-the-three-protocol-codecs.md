# TMB-009 — Implement and verify the three protocol codecs

**Status:** Done  
**Labels:** `protocol`, `controller-ios`, `controller-android`, `host`, `quality`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-004, TMB-005, TMB-006, TMB-008

### Implementation steps

1. Implement strict encode/decode functions in Swift.
2. Implement strict encode/decode functions in Kotlin.
3. Implement strict encode/decode functions in GDScript.
4. Run every implementation against all positive and negative fixtures.
5. Ensure decoding rejects non-finite sensor values and invalid quaternion data.

### Acceptance criteria

- All three implementations encode every golden message byte-for-byte.
- All three decode to equivalent values within documented floating-point tolerance.
- All negative fixtures are rejected with no crash.

### Evidence

- Test output from Swift, Kotlin and Godot
- Protocol v1 compatibility matrix

### Implementation log

- 2026-11-06: Added strict Swift, Kotlin and GDScript codecs with the same
  validation order and rejection codes as the specification.
- 2026-11-06: Each codec decoded and byte-for-byte re-encoded all eight positive
  fixtures and rejected all seven malformed fixtures without a crash.
- 2026-11-06: Cross-language worked-motion values passed the manifest tolerance;
  results are recorded in `docs/evidence/TMB-009-codec-compatibility.md`.


