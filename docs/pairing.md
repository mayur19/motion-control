# Pairing payload and host session

The desktop host creates a new ephemeral pairing session at launch and whenever
the operator chooses **New pairing code**. The QR contains this versioned URI:

```text
motion-badminton://join?v=1&host=<ipv4>&port=<udp>&session=<16-hex>&secret=<32-hex>&expires=<unix-seconds>
```

| Field | Meaning |
| --- | --- |
| `v` | Join-payload version. Version 1 is the only accepted value. |
| `host` | Selected, URI-encoded LAN IPv4 address. |
| `port` | UDP port in the range 1–65535. |
| `session` | Fresh nonzero 63-bit random session identifier, encoded as 16 hexadecimal digits. |
| `secret` | Fresh 128-bit random pairing secret, encoded as 32 lowercase hexadecimal digits. |
| `expires` | Absolute Unix-second expiry, 120 seconds after creation by default. |

The secret is an ephemeral proof for the `HELLO` handshake; it is not an account,
device, or long-lived credential. Creating or rotating a session replaces both
the session identifier and secret. A previous URI therefore cannot authorize a
controller in the new session. Controllers must reject expired, malformed, or
unknown-version payloads before sending `HELLO`.

The complete secret is also displayed as eight four-character groups for manual
entry when a camera is unavailable. The address and port remain visible beside
it. Group separators are presentation-only.

## Interface selection

The host enumerates non-loopback, non-link-local IPv4 addresses. Automatic
selection prefers an interface whose name does not look like a VPN or virtual
tunnel. Every usable address remains selectable so multi-homed development
machines can choose the LAN shared by the phones. Selecting a tunnel or VPN
keeps a visible reachability warning. If no usable address exists, QR generation
is disabled instead of advertising loopback.

## QR implementation

The host vendors Greaby's MIT-licensed pure-GDScript QR generator under
`apps/host-godot/addons/greaby_qrcode`; its license is included beside the
source. The renderer adds the standard four-module quiet zone and uses nearest
texture filtering so the code remains sharp at display size.
