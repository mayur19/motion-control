extends SceneTree

## Parses real `ifconfig awdl0` output captured on the M2 Pro host on
## 2026-11-06 (AWDL on, then after `sudo ifconfig awdl0 down`).

const Awdl = preload("res://session/awdl_detector.gd")

const ACTIVE := """awdl0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
	inet6 fe80::1%awdl0 prefixlen 64 scopeid 0x10
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect
	status: active
"""
const INACTIVE := """awdl0: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500
	options=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
	media: autoselect
	status: inactive
"""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if Awdl.parse_ifconfig(ACTIVE) != Awdl.State.ACTIVE:
		return _fail("active output not detected")
	if Awdl.parse_ifconfig(INACTIVE) != Awdl.State.INACTIVE:
		return _fail("inactive output not detected")
	if Awdl.parse_ifconfig("ifconfig: interface awdl0 does not exist") != Awdl.State.ABSENT:
		return _fail("missing interface not reported as absent")
	if Awdl.parse_ifconfig("") != Awdl.State.ABSENT:
		return _fail("empty output not reported as absent")
	if Awdl.warning_for(Awdl.State.INACTIVE) != "" or Awdl.warning_for(Awdl.State.ABSENT) != "":
		return _fail("warning shown when AWDL is off")
	var text := Awdl.warning_for(Awdl.State.ACTIVE)
	for needed in ["AirDrop", "Ethernet", "ifconfig awdl0 down"]:
		if not text.contains(needed):
			return _fail("warning lacks guidance '%s': %s" % [needed, text])
	if Awdl.combine_warnings("VPN selected.", "") != "VPN selected.":
		return _fail("combine dropped the network warning")
	if Awdl.combine_warnings("", "AWDL!") != "AWDL!" or Awdl.combine_warnings("A", "B") != "A\nB":
		return _fail("combine wrong")
	print("TMB-022_AWDL_DETECTOR_OK active=true inactive=true absent=true guidance=true")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("TMB-022_AWDL_DETECTOR_FAIL")
	quit(1)
