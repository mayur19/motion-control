# Controller heartbeat and reconnect

Each paired controller sends a `STATUS` datagram every 500 ms on its existing
UDP control path. The host treats any valid packet from the currently paired
endpoint as liveness, while `STATUS` also reports foreground and sensor state.

## Host states and thresholds

| State | Entry condition | Motion accepted |
| --- | --- | --- |
| `Reconnecting` | paired/repaired; waiting for status and fresh clock sync | No |
| `Connected` | active sensor status and initialized clock | Yes |
| `Degraded` | heartbeat older than 1 s, or invalid sensor state | No |
| `Paused` | controller reports background/paused | No |
| `Disconnected` | no valid packet for more than 2 s | No |

The host session is not restarted when a controller disconnects. The other
controller continues independently.

## Stable identity and endpoint changes

Each controller persists a random eight-hex-character installation identifier
and includes it in the HELLO device descriptor. It is not an OS advertising ID,
account identifier or hardware serial number. The host reserves the assigned
player/controller ID for a game-configurable reservation after disconnect
(default 30 s, 5-60 s; `--reconnect-window-s=N` or the
`network/reconnect/window_seconds` project setting, logged in `host_started`). A HELLO with the same
platform and installation descriptor within that window moves the assignment to
the new control endpoint. Controllers use a separate high-rate UDP socket; the
host pins its port on the first post-sync motion packet from the paired source IP
and resets that pin on reconnect. Packets from the prior stream are then ignored.
Because a new socket's sender-local sequence may start anywhere (iOS restarts it
at 0), the host starts a fresh duplicate/reorder/loss window when the admitted
motion endpoint changes, carrying the previous stream's loss into the total.

The reservation is deliberately in-memory and session-scoped. It is cleared by
host session reset and expires automatically, after which the player slot is
available to another controller.

When iOS returns to the foreground it recreates its Network.framework control
connection, repeats HELLO and retries for up to 60 seconds. A control path that
enters `waiting`/`failed` also rejoins when the network becomes ready. This is
separate from the high-rate motion socket: motion may recover first, but the host
keeps it gated until the control identity and fresh clock exchange are complete.

The QR's public join window may expire during a longer session. An expired code
cannot create a new assignment or take over an active identity, but it may
authenticate the same endpoint or a known installation reclaiming its active
configured disconnect reservation. This preserves bounded reconnect without
reopening the session to new controllers.

## Reconnect clock gate

On every reconnect the host discards that controller's previous clock estimate,
clears pending exchanges and immediately sends a new PING. Active status alone
cannot open the motion gate; a valid PONG from the new endpoint must initialize
the fresh estimator. This prevents timestamps measured on a changed path—or
after a controller process restart—from being interpreted using stale timing.
The same gate runs when an existing controller returns from background: its
motion-port pin is cleared, the clock estimator is reset, and input remains
paused until a fresh PONG initializes the path.

## Host liveness on the controller

The host also heartbeats the controllers. Every 500 ms it sends a host `STATUS`
(battery `255`, last accepted motion sequence) to each non-Disconnected
controller's control endpoint. On a clean window close it sends `GOODBYE` with
reason `3`, host shutdown (`network/host_heartbeat.gd`).

Each controller treats any valid host packet addressed to its session and
controller ID as proof that the host is alive. When nothing arrives within the
WELCOME `disconnect_timeout_ms` (2 s) while the app is in the foreground, the
controller leaves Connected, which stops motion streaming, and retries HELLO with
the same installation identity for up to 60 s (Android waits for Wi-Fi and binds
its sockets to it). A host that returns within its configured reservation
restores the same player; otherwise the controller reports
the host as unreachable. `GOODBYE` ends the pairing immediately and asks for a
new code. iOS and Android share this behavior (`HostLiveness`).
