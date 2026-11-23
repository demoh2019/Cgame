extends RefCounted
## Checks the exact Net RPC contract over SceneMultiplayer's pre-connection
## authentication channel. A mismatched peer must never reach gameplay RPCs.
## This is NOT account authentication; Nakama still validates the player later.

const PROTOCOL_EPOCH := 20261123
const AUTH_TIMEOUT_SECONDS := 20.0
const PREFIX := "albion-after-rpc:"


## Hash names, Godot transfer/authority flags, argument types and defaults.
## This catches incompatible RPCs even when Godot's built-in method-name
## checksum happens to match.
static func fingerprint(net: Node) -> String:
	var script: Script = net.get_script() as Script
	if script == null:
		return ""
	var config: Dictionary = script.get_rpc_config()
	if config.is_empty():
		return ""
	var methods: Dictionary = {}
	for raw_method in script.get_script_method_list():
		var method: Dictionary = raw_method
		methods[str(method.get("name", ""))] = method
	var entries: PackedStringArray = []
	for raw_name in config.keys():
		var name: String = str(raw_name)
		var rpc: Dictionary = config[raw_name]
		var signature: Dictionary = methods.get(name, {})
		var types: PackedStringArray = []
		for raw_arg in signature.get("args", []):
			var arg: Dictionary = raw_arg
			types.append(str(int(arg.get("type", TYPE_NIL))))
		var defaults: Array = signature.get("default_args", [])
		entries.append("%s|%d|%d|%d|%s|%s|%s" % [
			name, int(rpc.get("rpc_mode", 0)), int(rpc.get("transfer_mode", 0)),
			int(rpc.get("channel", 0)), str(bool(rpc.get("call_local", false))),
			",".join(types), JSON.stringify(defaults),
		])
	entries.sort()
	return ("%d\n%s" % [PROTOCOL_EPOCH, "\n".join(entries)]).sha256_text()


static func auth_payload(net: Node) -> PackedByteArray:
	var digest: String = fingerprint(net)
	if digest.is_empty():
		return PackedByteArray()
	return (PREFIX + digest).to_utf8_buffer()


static func accepts(net: Node, payload: PackedByteArray) -> bool:
	return not payload.is_empty() and payload == auth_payload(net)


## Both endpoints must install this BEFORE assigning the ENet peer.
## SceneMultiplayer keeps peers pending until each end calls complete_auth().
## Legacy builds that do not speak the handshake time out without any game RPC.
static func install(api: SceneMultiplayer, net: Node, rejected: Callable = Callable()) -> bool:
	if api == null:
		return false
	var payload: PackedByteArray = auth_payload(net)
	if payload.is_empty():
		return false
	api.auth_timeout = AUTH_TIMEOUT_SECONDS
	api.auth_callback = func(peer_id: int, received: PackedByteArray) -> void:
		if received != payload:
			if rejected.is_valid():
				rejected.call(peer_id)
			api.disconnect_peer(peer_id)
			return
		if api.complete_auth(peer_id) != OK:
			if rejected.is_valid():
				rejected.call(peer_id)
			api.disconnect_peer(peer_id)
	api.peer_authenticating.connect(func(peer_id: int) -> void:
		if api.send_auth(peer_id, payload) != OK:
			if rejected.is_valid():
				rejected.call(peer_id)
			api.disconnect_peer(peer_id)
	)
	return true
