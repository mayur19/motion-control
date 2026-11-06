# TMB-049 — Harden reconnect during an active match

**Status:** Blocked — active-match/safety dependencies incomplete  
**Labels:** `networking`, `gameplay`, `quality`  
**Estimate:** 1 day  
**Dependencies:** TMB-021, TMB-045, TMB-048

### Implementation steps

1. Preserve score, server and rally-safe pause state during disconnect.
2. Reconnect the original controller to the same player.
3. Re-synchronize time and require a quick readiness check before resume.
4. Define session-expiration behavior if reconnect does not occur.

### Acceptance criteria

- A mid-match Wi-Fi interruption does not corrupt score or assignment.
- No motion packets received before readiness can affect gameplay.
- Both players receive clear pause/resume feedback.

### Evidence

- iOS and Android mid-match reconnect test logs


