extends SceneTree

## Reproduces the 2026-11-06 Galaxy session: four controller IDs over one host
## session (reinstalls and an expired reservation). The HUD must show the live
## P1 controller in card 0, not the first IDs it ever saw.

const HudSlots = preload("res://ui/hud_slots.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var states := {
		1996523586: {"player": 1, "state": "Disconnected", "last_packet_age_ms": 560000},
		1107752041: {"player": 1, "state": "Disconnected", "last_packet_age_ms": 330000},
		2120019081: {"player": 1, "state": "Disconnected", "last_packet_age_ms": 285000},
		1465916994: {"player": 1, "state": "Connected", "last_packet_age_ms": 4},
	}
	var slots: Dictionary = HudSlots.assign(states.keys(), states)
	if slots != {1465916994: 0}:
		return _fail("live P1 not shown in card 0: %s" % str(slots))

	states[777] = {"player": 2, "state": "Paused", "last_packet_age_ms": 20}
	slots = HudSlots.assign(states.keys(), states)
	if slots != {1465916994: 0, 777: 1}:
		return _fail("P2 not shown in card 1: %s" % str(slots))

	# With only disconnected controllers for a player, the most recent one is shown.
	var stale := {
		1: {"player": 1, "state": "Disconnected", "last_packet_age_ms": 9000},
		2: {"player": 1, "state": "Disconnected", "last_packet_age_ms": 3000},
	}
	if HudSlots.assign(stale.keys(), stale) != {2: 0}:
		return _fail("most recent disconnected controller not preferred")

	# Unassigned or rejected controllers (player 0) never take a card.
	var unassigned := {5: {"player": 0, "state": "Disconnected", "last_packet_age_ms": 1}}
	if not HudSlots.assign(unassigned.keys(), unassigned).is_empty():
		return _fail("player 0 took a card")
	print("TMB-013_HUD_SLOTS_OK by_player=true live_preferred=true")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("TMB-013_HUD_SLOTS_FAIL")
	quit(1)
