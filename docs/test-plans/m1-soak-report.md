# M1 simultaneous-controller soak report

**Status:** Run B (Wi-Fi host) executed; Run A (Ethernet) pending: no Ethernet available  
**Ticket:** TMB-022  
**Operator/date:** project owner, 2026-11-06  
**Build revision:** uncommitted working tree on top of `a76086d` (all session fixes applied)  
**Owner decisions (2026-11-06):** each run is **5 minutes with normal movement** instead of 10. Rate threshold: **median accepted rate >= 99 Hz per phone**. Frame stall: **no frame over 150 ms and frame-time p99 under 50 ms**. Loss + late stays below 1%.

## Purpose and pass criteria

Run the same ten-minute, two-controller workload twice: first with the host on
wired Ethernet, then with the host on 5/6 GHz Wi-Fi. Each phone must sustain at
least 100 accepted motion samples/second, dropped or late packets must remain
below 1%, memory must remain bounded, and the host must not crash or exhibit a
frame stall. Results from the two topologies are reported separately.

## Fixed setup

- Record host OS/model, Godot build, display refresh and power mode.
- Record phone model, OS/app build, battery start/end and charger state.
- Record router/AP model, firmware, channel, channel width and band.
- Disable VPN, cellular fallback/hotspot and battery-saving modes.
- Put both phones on the same 5 or 6 GHz SSID; verify client isolation is off.
- For run A connect the host by Ethernet and disable host Wi-Fi.
- For run B disconnect Ethernet and join the host to that same SSID.
- Keep phone/AP/host placement and the movement script unchanged between runs.

Start the host with enough bounded space for the full packet log:

```sh
godot --path apps/host-godot -- --session-log-max-mb=128
```

The default log directory is the Godot user-data `logs` directory. Copy each
JSONL immediately after the run and record its SHA-256 checksum below.

## Execution

1. Start a new host session and pair both phones; verify P1/P2 are Connected.
2. Confirm both controller debug views report sampling/streaming and the host
   HUD shows synchronized sample age.
3. Record a 30-second idle baseline.
4. Start a ten-minute timer. Both operators continuously alternate ordinary
   forehand, backhand, overhead and underhand movements without striking objects.
5. At 2:30, 5:00 and 7:30 record a host HUD photograph. Do not background apps.
6. At 10:00 stop movement, record a final HUD photograph, then close the host
   cleanly so the JSONL flushes.
7. Check the log contains `soak_metrics` through the end of the full interval and
   no `logging_disabled`/size-limit truncation. Repeat for the second topology.

## Run A — Ethernet host

| Field | P1 | P2 |
| --- | ---: | ---: |
| Controller-reported sensor Hz, median/min | _pending_ | _pending_ |
| Accepted motion Hz, median/min | _pending_ | _pending_ |
| Packets received / inferred lost | _pending_ | _pending_ |
| Loss + late percentage | _pending_ | _pending_ |
| Duplicate / reordered | _pending_ | _pending_ |
| RTT median/p95, ms | _pending_ | _pending_ |
| Network jitter median/p95, ms | _pending_ | _pending_ |
| Sample age median/p95/max, ms | _pending_ | _pending_ |

Host frame time median/p95/max: _pending_  
Static memory start/peak/end: _pending_  
Queue drops / disconnects / crashes: _pending_  
Raw log path and SHA-256: _pending_

## Run B — Wi-Fi host

Setup: host Mac14,9 (Apple M2 Pro), macOS 26.6.2, Godot 4.7.2, Wi-Fi only:
5 GHz channel 48, 80 MHz, 802.11ac, -47 dBm. P1 iPhone 17e (iOS app, 100 Hz
design rate); P2 Samsung Galaxy M14 5G SM-M146B, Android 15 (250 Hz delivered).
The phones' Wi-Fi band was not verifiable from the tools (same SSID as the host).
Both phones were moved by hand, apps in the foreground, in one host session
(`session-2026-11-06 13-12-00-097E3B646B83234D.jsonl`). Analysis:
`python3 -I tools/soak-report.py <log> <start_s> [end_s]`.

Two sub-runs isolate a host-side cause found in B1 (see disposition).

### B1: macOS AWDL active (default), 306 s (host 823.3-1129.7 s)

| Field | P1 iPhone | P2 Galaxy |
| --- | ---: | ---: |
| Controller-reported sensor Hz, median | 101 | 250 |
| Accepted motion Hz, median/min | 100.0 / 69.4 | 249.1 / 91.1 |
| Packets accepted / inferred lost | ~30,595 / 91 | ~75,768 / 572 |
| Late (>50 ms) samples | 7,464 (24.4%) | 17,175 (22.6%) |
| Loss + late percentage | **24.6%, FAIL** | **23.2%, FAIL** |
| Duplicate / reordered | 0 / 0 | 0 / 0 |
| RTT median/max, ms | 17.0 / 19.1 | 16.8 / 18.8 |
| Network jitter median/max, ms | 16.8 / 35.1 | 6.4 / 16.4 |
| Sample age median/p95/p99/max, ms | 16.5 / 102.4 / 235.2 / 541.6 | 15.0 / 91.1 / 169.7 / 420.5 |

Host frame median/p95/worst: 13.9 / 21.2 / 106.4 ms (one-off; the per-second
maximum is about 25 ms). Static memory 43.1 to 43.2 MB (+0.18%). Queue drops 0.
P2: one Degraded blip at 908.0 s, recovered at 908.6 s. No crashes.

Late samples came in ~100 ms bursts **every 0.52 s on both phones at once**.
Host frames did not stall on that rhythm, so the delay was in the Mac's Wi-Fi
receive path.

### B2: macOS AWDL disabled (`sudo ifconfig awdl0 down`), 198 s (host 1143.8-1341.6 s)

| Field | P1 iPhone | P2 Galaxy |
| --- | ---: | ---: |
| Controller-reported sensor Hz, median | 101 | 250 |
| Accepted motion Hz, median/min | 100.0 / 98.8 | 249.2 / 246.1 |
| Packets accepted / inferred lost | ~19,797 / 4 | ~49,313 / 0 |
| Late (>50 ms) samples | 20 (0.10%) | 86 (0.17%) |
| Loss + late percentage | **0.121%, PASS** | **0.174%, PASS** |
| Duplicate / reordered | 0 / 0 | 0 / 0 |
| RTT median/max, ms | 17.2 / 17.7 | 16.5 / 17.2 |
| Network jitter median/max, ms | 17.7 / 19.1 | 6.6 / 7.3 |
| Sample age median/p95/p99/max, ms | 10.1 / 19.6 / 22.9 / 163.9 | 9.5 / 19.5 / 26.7 / 161.0 |

Host frame median/p95/worst: 17.7 / 21.3 / 134.6 ms (one-off). Static memory
43.2 MB (+0.00%). Queue drops 0. No state changes, disconnects or crashes.

Raw log (closed cleanly, 422,323 lines) SHA-256:
`f837405a056fcecdcd8177d8235718732388d16c77cc609d85c24f988393f79e`

## Comparison and disposition

Two-wireless-hop penalty (Wi-Fi minus Ethernet): _pending_ until Run A.

Findings:
1. **macOS AWDL (AirDrop/Continuity) is the dominant cause of late input on a
   Wi-Fi Mac host.** Disabling it cut late samples from about 23% to about
   0.15% and sample-age p95 from about 100 ms to about 20 ms on both phones.
   Product follow-up: detect `awdl0` active on a Wi-Fi host and warn the
   operator (or document "turn off AirDrop/Handoff"); prefer an Ethernet host.
2. Rate: P1 median 100.0 Hz and P2 249 Hz; both PASS the owner's median
   >= 99 Hz threshold in both sub-runs.
3. Frame stall: the worst frames were 106.4 ms (B1) and 134.6 ms (B2), both
   <= 150 ms. These logs predate per-second frame p99, so a strict upper bound
   is used: at most 80 of 30,157 (B1) and 140 of 19,529 (B2) frames could
   exceed 50 ms, under 1% in both, so p99 < 50 ms. PASS. The host now logs
   per-second p99 for future runs.
4. A Galaxy controller once failed to receive WELCOME (not reproducible;
   instrumented). See TMB-021 evidence.

Final result (`tools/soak-report.py`):
- **Run B2, Wi-Fi host with AWDL disabled: PASS** (`TMB-022_SOAK_PASS`): rate,
  loss + late (0.121% / 0.174%), memory (+0.00%), queue drops 0, frame stall.
  This was a 198 s window, shorter than the 5-minute target.
- **Run B1, Wi-Fi host with default macOS (AWDL on): FAIL** on loss + late
  (24.6% / 23.2%); every other criterion passes.
- **Overall TMB-022: NOT YET PASSED.** Run A (Ethernet host) is pending, and B2
  ran for 3.3 of the agreed 5 minutes.
