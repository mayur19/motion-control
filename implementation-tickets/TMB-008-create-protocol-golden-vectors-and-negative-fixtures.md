# TMB-008 — Create protocol golden vectors and negative fixtures

**Status:** Done  
**Labels:** `protocol`, `quality`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-007

### Implementation steps

1. Create at least one binary golden packet for every message type.
2. Add a machine-readable manifest containing expected decoded field values.
3. Add truncated, wrong-version, invalid-enum, invalid-length and non-finite-float fixtures.
4. Document how to add fixtures without silently changing existing protocol behavior.

### Acceptance criteria

- Golden packet bytes are stable and version controlled.
- Each negative fixture has an expected rejection reason.
- Fixtures can be consumed without platform-specific tooling.

### Evidence

- `protocol/golden-vectors/`
- Fixture manifest and README

### Implementation log

- 2026-11-06: Added eight positive binary datagrams, one for every message, and
  seven deterministic malformed fixtures covering every required failure class.
- 2026-11-06: Added a JSON manifest with decoded expectations, rejection codes,
  SHA-256 hashes and float tolerance.
- 2026-11-06: Added deterministic regeneration/check tooling and verified all
  15 fixture files byte-for-byte.


