# TMB-022 — Run the M1 simultaneous-controller soak test

**Status:** Deferred — physical devices required  
**Labels:** `quality`, `observability`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-013, TMB-015, TMB-017, TMB-021

### Implementation steps

1. Connect the host by Ethernet and both phones by 5/6 GHz Wi-Fi.
2. Stream both phones simultaneously for 10 minutes while performing normal controller movements.
3. Record actual sensor rate, received rate, loss, duplicate, reorder, RTT, jitter, sample age and host frame time.
4. Repeat once with the host on Wi-Fi to measure the two-wireless-hop penalty.
5. Record defects and identify any metric that misses the PRD threshold.

### Acceptance criteria

- Ethernet-host run sustains at least 100 Hz per phone.
- Dropped/late packets are below 1% per phone.
- No unbounded memory growth, crash or host frame stall occurs.
- Ethernet and Wi-Fi host results are reported separately.

### Evidence

- `docs/test-plans/m1-soak-report.md`
- [Automated telemetry pipeline verification](../docs/evidence/TMB-022-soak-telemetry.txt)
- Raw logs for both runs

### Implementation log

- 2026-11-06: Added bounded once-per-second `soak_metrics` records containing
  sensor/received rate, loss, duplicates, reorder, RTT, jitter, sample age,
  host frame time, memory and queue health. Added a command-line log-size
  override and a complete two-topology execution/report template.
- Execution is deferred by explicit project-owner direction until both physical
  phones are available. No emulator or synthetic traffic is substituted for the
  required simultaneous radio/sensor soak evidence.


- 2026-11-06: Owner decision: the simultaneous soak runs for **5 minutes with
  normal movement** instead of 10, because 10 minutes of continuous swinging is
  impractical for a human tester. The acceptance thresholds are unchanged. A
  first attempt was abandoned after 121 s because the Galaxy received a phone
  call; its data is reported as a partial segment only. The host is Wi-Fi only
  (no Ethernet available), so the Ethernet-host run remains open.
- 2026-11-06: Run B (Wi-Fi host) executed with the physical iPhone 17e (P1) and
  Galaxy M14 5G (P2); see `docs/test-plans/m1-soak-report.md` and
  `tools/soak-report.py`. With default macOS (AWDL active), loss + late was
  about 24% per phone, caused by ~100 ms receive delays every 0.52 s on the Mac.
  With AWDL disabled, both phones passed at 0.12% and 0.17%, sample-age p95
  about 20 ms, memory flat, no queue drops and no crashes. Open: Run A
  (Ethernet), the P1 >= 100 Hz criterion at the iPhone's exact 100 Hz design
  rate, and the definition of "frame stall" (single 106 ms and 135 ms frames
  were observed).
- 2026-11-06: Owner thresholds applied in `tools/soak-report.py`: median rate
  >= 99 Hz, no frame over 150 ms, frame p99 < 50 ms (a strict upper bound is
  used for logs without p99). Host telemetry now logs per-second p99. Run B2
  (AWDL off): `TMB-022_SOAK_PASS`. Run B1 (AWDL on): FAIL on loss + late only.
  The tool double-counted host frames per controller and treated idle IDs as
  failures; both fixed, with tests.
- 2026-11-06: Per owner direction, the host detects macOS AWDL
  (`ifconfig awdl0` status), shows a wrapping warning with turn-off guidance
  on the pairing panel, re-checks every 3 s and logs `awdl_state` events
  (`session/awdl_detector.gd`, `tests/awdl_detector_test.gd`). Setup guidance
  is in `docs/development.md`. The host never disables AWDL itself.
- 2026-11-06: The owner confirmed on the physical host that the amber AWDL
  warning appears on the pairing panel while AWDL is active.
