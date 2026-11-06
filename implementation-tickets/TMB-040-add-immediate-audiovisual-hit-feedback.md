# TMB-040 — Add immediate audiovisual hit feedback

**Status:** Blocked — shuttle-hit dependency incomplete  
**Labels:** `gameplay`, `observability`  
**Estimate:** 1 day  
**Dependencies:** TMB-039

### Implementation steps

1. Add an immediate visual/audio acknowledgement at the accepted swing trigger.
2. Add distinct later feedback for perfect, weak, late and miss outcomes.
3. Instrument the first visible feedback frame.
4. Ensure effects do not introduce input or simulation delay.

### Acceptance criteria

- Initial feedback starts on the earliest accepted trigger.
- Outcome feedback is distinguishable without reading debug text.
- Effects maintain the reference frame-time target.

### Evidence

- Instrumented gameplay clip
- Frame-time capture


