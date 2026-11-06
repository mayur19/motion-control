# TMB-056 — Add automated build and test workflows

**Status:** Blocked — release export dependency incomplete  
**Labels:** `release`, `quality`, `foundation`  
**Estimate:** 1.5 days  
**Dependencies:** TMB-009, TMB-055

### Implementation steps

1. Run protocol tests for Swift, Kotlin and GDScript on each main-branch change.
2. Run host headless smoke and deterministic gameplay tests.
3. Build Android and host debug artifacts where runners support them.
4. Add iOS build/test on a suitable macOS runner.
5. Retain logs and failed test artifacts.

### Acceptance criteria

- A protocol-breaking change fails before merge.
- A failed deterministic gameplay test preserves enough evidence to diagnose it.
- Workflow secrets/signing material are not stored in the repository.

### Evidence

- Successful workflow run
- Intentional failure demonstration


