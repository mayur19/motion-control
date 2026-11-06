extends RefCounted

## Builds the session-log fields for a pairing outcome.
## Uses an explicit allow-list so secrets, installation identities and device
## models in the source event can never reach the engineering log.


static func from_event(event: Dictionary) -> Dictionary:
	return {
		"controller_id": int(event.get("controller_id", 0)),
		"player": int(event.get("player", 0)),
		"state": int(event.get("state", 0)),
		"reason": str(event.get("reason", "")),
		"endpoint": str(event.get("endpoint", "")),
		"platform": int(event.get("platform", 0)),
	}
