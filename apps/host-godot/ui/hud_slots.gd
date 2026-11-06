extends RefCounted

## Chooses which controller each diagnostics card shows. Card index is the
## assigned player minus one, so reconnects, reinstalls and expired reservations
## (each of which can mint a new controller ID) never strand a card on a dead
## ID. Per player, a non-Disconnected controller wins; ties go to the most
## recently heard controller.

const PLAYER_COUNT := 2
const SILENT_STATE := "Disconnected"


## Returns {controller_id: card_index}. `states` maps controller_id to a
## connection-manager state containing player, state and last_packet_age_ms.
static func assign(controller_ids: Array, states: Dictionary) -> Dictionary:
	var best_by_slot := {}
	for raw_id in controller_ids:
		var controller_id := int(raw_id)
		var state: Dictionary = states.get(controller_id, {})
		var player := int(state.get("player", 0))
		if player < 1 or player > PLAYER_COUNT:
			continue
		var slot := player - 1
		var candidate := {
			"id": controller_id,
			"live": str(state.get("state", SILENT_STATE)) != SILENT_STATE,
			"age": float(state.get("last_packet_age_ms", INF)),
		}
		if not best_by_slot.has(slot) or _outranks(candidate, best_by_slot[slot]):
			best_by_slot[slot] = candidate
	var result := {}
	for slot in best_by_slot:
		result[int(best_by_slot[slot].id)] = int(slot)
	return result


static func _outranks(candidate: Dictionary, current: Dictionary) -> bool:
	if bool(candidate.live) != bool(current.live):
		return bool(candidate.live)
	return float(candidate.age) < float(current.age)
