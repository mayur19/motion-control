extends SceneTree

const SessionManager = preload("res://session/session_manager.gd")
const QrCodeGenerator = preload("res://addons/greaby_qrcode/qr_code.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var interfaces := [
		{"name": "lo0", "friendly": "Loopback", "addresses": ["127.0.0.1", "::1"]},
		{"name": "utun4", "friendly": "VPN Tunnel", "addresses": ["10.8.0.2"]},
		{"name": "en0", "friendly": "Wi-Fi", "addresses": ["192.168.50.12", "fe80::1"]},
		{"name": "bridge0", "friendly": "Bridge", "addresses": ["169.254.1.2"]},
	]
	var candidates := SessionManager.discover_interfaces(interfaces)
	if candidates.size() != 2:
		_fail("Expected LAN and VPN candidates, got %s" % str(candidates))
		return
	var automatic := SessionManager.select_interface(candidates)
	if automatic.name != "en0" or automatic.address != "192.168.50.12" or automatic.risky:
		_fail("Automatic selection did not prefer safe LAN: %s" % str(automatic))
		return
	var explicit_vpn := SessionManager.select_interface(candidates, "utun4")
	if not explicit_vpn.risky or str(explicit_vpn.warning).is_empty():
		_fail("Explicit VPN selection did not retain a warning")
		return

	var manager := SessionManager.new()
	root.add_child(manager)
	var first := manager.start_new_session(7000, "", interfaces, 1_800_000_000)
	var parsed := SessionManager.parse_join_uri(first.join_uri)
	if not parsed.ok:
		_fail("Generated URI did not parse: %s" % str(parsed))
		return
	if (
		parsed.fields.host != "192.168.50.12"
		or int(parsed.fields.port) != 7000
		or parsed.fields.session != first.session_hex
		or parsed.fields.secret != first.secret
		or int(parsed.fields.expires) != 1_800_000_120
	):
		_fail("Generated URI fields changed during parse")
		return
	if manager.is_expired(1_800_000_119) or not manager.is_expired(1_800_000_120):
		_fail("Pairing-secret expiry boundary is wrong")
		return
	var second := manager.rotate("en0", 1_800_000_030)
	if second.secret == first.secret or second.session_hex == first.session_hex:
		_fail("New session did not invalidate both old credentials")
		return
	if second.manual_code.replace("-", "").to_lower() != second.secret:
		_fail("Manual code does not carry the complete pairing secret")
		return

	var qr := QrCodeGenerator.new()
	root.add_child(qr)
	var texture := qr.get_texture(first.join_uri)
	if texture == null or texture.get_width() < 29 or texture.get_width() != texture.get_height():
		_fail("QR generator returned an invalid texture")
		return
	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	if not output_path.is_empty():
		var save_error := texture.get_image().save_png(output_path)
		if save_error != OK:
			_fail("Could not save QR evidence: %s" % error_string(save_error))
			return

	print(
		"TMB-018_SESSION_OK candidates=%d selected=%s vpn_warning=true rotated=true qr=%dx%d uri=%s" % [
			candidates.size(), automatic.name, texture.get_width(), texture.get_height(), first.join_uri,
		]
	)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
