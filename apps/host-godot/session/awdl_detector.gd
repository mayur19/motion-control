extends RefCounted

## Detects macOS AWDL (Apple Wireless Direct Link: AirDrop, AirPlay, Continuity,
## Sidecar, Universal Control). While active it periodically takes the Wi-Fi
## radio off-channel; on a Wi-Fi host this delayed ~23% of controller samples by
## ~100 ms every 0.52 s in the TMB-022 soak (0.15% with AWDL off). The host only
## warns; disabling AWDL needs admin rights and is the operator's choice.

enum State { ABSENT, INACTIVE, ACTIVE }

const INTERFACE := "awdl0"
const IFCONFIG := "/sbin/ifconfig"
const WARNING := (
	"AirDrop/Continuity (AWDL) is active and delays controller input when this Mac "
	+ "hosts over Wi-Fi. Use Ethernet, or turn it off: Control Centre > AirDrop > "
	+ "No One, and System Settings > General > AirDrop & Handoff > Handoff off. "
	+ "If this warning stays, run `sudo ifconfig awdl0 down` "
	+ "(undo: `sudo ifconfig awdl0 up`; a reboot also restores it)."
)


## Reads the live state. Non-macOS hosts have no AWDL.
static func current_state() -> State:
	if OS.get_name() != "macOS":
		return State.ABSENT
	var output: Array = []
	var exit_code := OS.execute(IFCONFIG, [INTERFACE], output, true)
	if exit_code != 0 or output.is_empty():
		return State.ABSENT
	return parse_ifconfig(str(output[0]))


static func parse_ifconfig(text: String) -> State:
	if not text.begins_with(INTERFACE + ":"):
		return State.ABSENT
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("status:"):
			return State.ACTIVE if trimmed.trim_prefix("status:").strip_edges() == "active" else State.INACTIVE
	return State.INACTIVE


static func warning_for(state: State) -> String:
	return WARNING if state == State.ACTIVE else ""


static func combine_warnings(network_warning: String, awdl_warning: String) -> String:
	var parts := PackedStringArray()
	for part in [network_warning, awdl_warning]:
		if not str(part).is_empty():
			parts.append(str(part))
	return "\n".join(parts)


static func state_name(state: State) -> String:
	return ["absent", "inactive", "active"][state]
