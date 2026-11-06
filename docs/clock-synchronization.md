# Monotonic clock synchronization

The host periodically sends protocol `PING` messages immediately after pairing
and every five seconds while a controller remains assigned. A controller records
its native monotonic receive time, records another monotonic time immediately
before replying, and returns all three values in `PONG`. The host adds its local
receive time to form the standard four-timestamp exchange:

```text
t1 host send -> t2 controller receive -> t3 controller send -> t4 host receive
```

The estimator computes:

```text
RTT = (t4 - t1) - (t3 - t2)
controller_minus_host_offset = ((t2 - t1) + (t3 - t4)) / 2
host_time = controller_time - offset
```

It retains the latest 32 valid exchanges, ranks them by RTT, and selects the
median offset from the lowest-RTT quartile. Normal updates are smoothed with an
alpha of 0.2. A change larger than 5 ms is applied immediately and remains
visible rather than being hidden by smoothing. Drift is the selected offset
change divided by host elapsed time, reported in parts per million. Drift
baselines advance only when the selected low-RTT sample moves forward by at
least one second; reordered selection among rapid startup exchanges cannot
produce a misleading large ppm spike.

Adjusted sample time is never allowed to move backward silently. If conversion
would be equal to or older than the preceding converted sample, it is clamped to
the previous result plus one nanosecond and a `backward_corrections` counter is
incremented. Until one exchange succeeds, samples are explicitly marked
unsynchronized and their adjusted age is `-1`.

## Synthetic tolerance

Symmetric-delay tests require offset error below 0.05 ms and exact RTT within
0.001 ms. Network clock exchange cannot independently observe path asymmetry;
the theoretical offset error is half the one-way-delay difference. The automated
4 ms/8 ms path test therefore expects the documented 2 ms bias. The five-minute
100 ppm drift test tolerates 0.1 ppm.

Each successful exchange is logged as a `clock_sync` event with controller ID,
sample count, RTT, offset, drift and backward-correction count. Accepted motion
samples carry `clock_synchronized`, `adjusted_host_monotonic_ns`, and
`adjusted_sample_age_ms` in the host pipeline.
