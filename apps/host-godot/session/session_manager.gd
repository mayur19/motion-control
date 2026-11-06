class_name HostSessionManager
extends Node

const JOIN_SCHEME := "motion-badminton://join"
const JOIN_VERSION := 1
const DEFAULT_LIFETIME_SECONDS := 120
const RISKY_INTERFACE_MARKERS := ["utun", "tun", "tap", "vpn", "wg", "tailscale", "zerotier"]

var lifetime_seconds := DEFAULT_LIFETIME_SECONDS
var current_session: Dictionary = {}
var available_interfaces: Array[Dictionary] = []


func start_new_session(
	port: int,
	preferred_interface := "",
	interfaces: Array = [],
	now_unix_seconds := -1
) -> Dictionary:
	if now_unix_seconds < 0:
		now_unix_seconds = int(Time.get_unix_time_from_system())
	available_interfaces = discover_interfaces(interfaces)
	var selected := select_interface(available_interfaces, preferred_interface)
	var session_id := _nonzero_random_u64()
	var secret := _random_hex(16)
	current_session = {
		"session_id": session_id,
		"session_hex": "%016X" % session_id,
		"secret": secret,
		"created_unix_s": now_unix_seconds,
		"expires_unix_s": now_unix_seconds + lifetime_seconds,
		"port": port,
		"interface_name": selected.get("name", ""),
		"interface_friendly": selected.get("friendly", ""),
		"address": selected.get("address", ""),
		"network_warning": selected.get("warning", "No usable LAN interface was found."),
	}
	current_session["join_uri"] = build_join_uri(current_session)
	current_session["manual_code"] = _group_code(secret)
	return current_session.duplicate(true)


func rotate(preferred_interface := "", now_unix_seconds := -1) -> Dictionary:
	return start_new_session(
		int(current_session.get("port", 7000)),
		preferred_interface,
		available_interfaces,
		now_unix_seconds
	)


func is_expired(now_unix_seconds := -1) -> bool:
	if current_session.is_empty():
		return true
	if now_unix_seconds < 0:
		now_unix_seconds = int(Time.get_unix_time_from_system())
	return now_unix_seconds >= int(current_session.expires_unix_s)


static func build_join_uri(session: Dictionary) -> String:
	var address := str(session.get("address", ""))
	if address.is_empty():
		return ""
	return "%s?v=%d&host=%s&port=%d&session=%s&secret=%s&expires=%d" % [
		JOIN_SCHEME,
		JOIN_VERSION,
		address.uri_encode(),
		int(session.port),
		str(session.session_hex),
		str(session.secret),
		int(session.expires_unix_s),
	]


static func parse_join_uri(uri: String) -> Dictionary:
	if not uri.begins_with(JOIN_SCHEME + "?"):
		return {"ok": false, "error": "INVALID_SCHEME"}
	var fields := {}
	for pair in uri.get_slice("?", 1).split("&", false):
		if pair.get_slice_count("=") != 2:
			return {"ok": false, "error": "MALFORMED_FIELD"}
		fields[pair.get_slice("=", 0)] = pair.get_slice("=", 1).uri_decode()
	for required in ["v", "host", "port", "session", "secret", "expires"]:
		if not fields.has(required) or str(fields[required]).is_empty():
			return {"ok": false, "error": "MISSING_FIELD"}
	if int(fields.v) != JOIN_VERSION:
		return {"ok": false, "error": "UNSUPPORTED_VERSION"}
	if not str(fields.host).is_valid_ip_address():
		return {"ok": false, "error": "INVALID_HOST"}
	if int(fields.port) < 1 or int(fields.port) > 65535:
		return {"ok": false, "error": "INVALID_PORT"}
	if not _is_hex(str(fields.session), 16) or not _is_hex(str(fields.secret), 32):
		return {"ok": false, "error": "INVALID_CREDENTIAL"}
	if int(fields.expires) <= 0:
		return {"ok": false, "error": "INVALID_EXPIRY"}
	return {"ok": true, "fields": fields}


static func discover_interfaces(source: Array = []) -> Array[Dictionary]:
	if source.is_empty():
		source = IP.get_local_interfaces()
	var result: Array[Dictionary] = []
	for raw_interface in source:
		var interface: Dictionary = raw_interface
		var name := str(interface.get("name", "unknown"))
		var friendly := str(interface.get("friendly", name))
		var lower_name := (name + " " + friendly).to_lower()
		var risky := false
		for marker in RISKY_INTERFACE_MARKERS:
			if lower_name.contains(marker):
				risky = true
				break
		for raw_address in interface.get("addresses", []):
			var address := str(raw_address)
			if not _usable_ipv4(address):
				continue
			result.append({
				"name": name,
				"friendly": friendly,
				"address": address,
				"risky": risky,
				"warning": "VPN or virtual interface selected; verify phone reachability." if risky else "",
			})
	return result


static func select_interface(candidates: Array[Dictionary], preferred_name := "") -> Dictionary:
	if not preferred_name.is_empty():
		for candidate in candidates:
			if candidate.name == preferred_name:
				return candidate.duplicate(true)
	for candidate in candidates:
		if not bool(candidate.risky):
			return candidate.duplicate(true)
	if not candidates.is_empty():
		return candidates[0].duplicate(true)
	return {
		"name": "",
		"friendly": "",
		"address": "",
		"risky": true,
		"warning": "No usable LAN IPv4 interface; pairing QR is disabled.",
	}


static func _usable_ipv4(address: String) -> bool:
	return (
		address.is_valid_ip_address()
		and address.contains(".")
		and not address.begins_with("127.")
		and not address.begins_with("169.254.")
		and address != "0.0.0.0"
	)


static func _is_hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for character in value.to_lower():
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _nonzero_random_u64() -> int:
	var bytes := Crypto.new().generate_random_bytes(8)
	# Keep the top bit clear because GDScript integers are signed, while retaining
	# 63 bits of cryptographic entropy and protocol wire compatibility.
	bytes[0] &= 0x7F
	var result := 0
	for byte in bytes:
		result = (result << 8) | int(byte)
	return result if result != 0 else 1


func _random_hex(byte_count: int) -> String:
	return Crypto.new().generate_random_bytes(byte_count).hex_encode()


func _group_code(secret: String) -> String:
	var groups: Array[String] = []
	for offset in range(0, secret.length(), 4):
		groups.append(secret.substr(offset, 4).to_upper())
	return "-".join(groups)
