# TMB-012 — Add structured host session logging

**Status:** Done  
**Labels:** `observability`, `host`  
**Estimate:** 1 day  
**Dependencies:** TMB-011

### Implementation steps

1. Define a versioned line-oriented or similarly stream-safe log schema.
2. Write a session header containing application, protocol, OS and device metadata.
3. Log packet sequence, sensor time, arrival time, size and validation result.
4. Flush safely at intervals so a crash does not lose the complete session.
5. Add log rotation or explicit maximum-size behavior.

### Acceptance criteria

- A 10-minute, two-controller run produces a readable, bounded log.
- A partially written final record does not invalidate earlier records.
- Logging can be disabled and does not contain audio, video or account data.

### Evidence

- Log schema documentation
- Sample session log and size report

### Implementation log

- 2026-11-06: Added schema-v1 JSON Lines session, packet and event records with
  application, protocol, host, device/network timing and validation metadata.
- 2026-11-06: Added one-second periodic flush, clean-close flush, disabled mode
  and a pre-write byte ceiling that closes the log without a partial record.
- 2026-11-06: Verified 22 readable sample records (5,798 bytes), a 2,048-byte
  stress ceiling (2,006 actual bytes) and zero file creation when disabled.


