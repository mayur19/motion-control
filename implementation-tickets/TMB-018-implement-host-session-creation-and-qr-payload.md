# TMB-018 — Implement host session creation and QR payload

**Status:** Done  
**Labels:** `networking`, `host`, `security`  
**Estimate:** 1 day  
**Dependencies:** TMB-009, TMB-011

### Implementation steps

1. Generate a random session ID and short-lived pairing secret.
2. Select a usable LAN interface and show the chosen IP and port.
3. Encode protocol version, address, port, session and secret in a versioned join URI.
4. Render the join URI as a QR code and provide a manual code fallback.
5. Expire and rotate the secret when the host starts a new session.
6. Add interface selection when VPN/virtual/multiple adapters are present.

### Acceptance criteria

- The QR payload contains no long-lived credential.
- The host does not advertise loopback, VPN or unreachable interfaces without warning.
- Starting a new session invalidates the old pairing secret.
- Manual join information is available when camera scanning is unavailable.

### Evidence

- [QR payload specification](../docs/pairing.md)
- [Automated multi-interface/session test and independent QR decode](../docs/evidence/TMB-018-host-session.txt)
- [Rendered 1080p host pairing panel](../docs/evidence/TMB-018-host-pairing.png)

### Implementation log

- 2026-11-06: Added ephemeral session ID/secret creation, 120-second expiry,
  versioned join URI, strict parser, secret rotation, complete manual fallback,
  safe LAN interface preference and explicit multi-interface selection.
- 2026-11-06: Added an MIT-licensed pure-GDScript QR renderer. The QR shown in
  the full host screenshot was independently decoded back to the exact join URI.


