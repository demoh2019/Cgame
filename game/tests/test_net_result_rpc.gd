extends RefCounted
## Verify current RPC replies, older single-argument envelopes, and safe
## handling of malformed replies without guessing command outcomes.

const Net = preload("res://scripts/shared/net.gd")
const NetProtocol = preload("res://scripts/shared/net_protocol.gd")


func run(t) -> void:
	t.current = "server result RPC keeps current and older envelope formats"
	var net: Node = Net.new()
	var delivered: Array = []
	net.connect("result_received", func(kind: String, data: Dictionary) -> void:
		delivered.append({"kind": kind, "data": data})
	)
	# callv uses the same Object.callp() argument-count path as incoming RPC.
	net.callv("s_result", ["craft", {"ok": true, "count": 2}])
	t.eq(delivered.size(), 1, "current two-argument result dispatches")
	t.eq(delivered[0]["kind"], "craft", "current command kind preserved")
	t.eq(delivered[0]["data"], {"ok": true, "count": 2}, "current result preserved")
	net.callv("s_result", [{"kind": "gather", "data": {"ok": false, "reason": "full"}}])
	t.eq(delivered.size(), 2, "older one-argument envelope dispatches")
	t.eq(delivered[1]["kind"], "gather", "legacy command kind preserved")
	t.eq(delivered[1]["data"]["reason"], "full", "legacy result preserved")

	t.current = "malformed and ambiguous result packets fail closed"
	t.eq(Net.normalize_result_packet("craft"), {},
		"one-argument string has no result and cannot be trusted")
	t.eq(Net.normalize_result_packet({"ok": true}), {},
		"unwrapped dictionary cannot be assigned to an unknown command")
	t.eq(Net.normalize_result_packet("craft", ["not a dictionary"]), {},
		"wrong payload type is rejected")
	t.eq(Net.normalize_result_packet({"kind": "craft", "data": []}), {},
		"bad legacy envelope is rejected")
	net.callv("s_result", ["craft"])
	net.callv("s_result", [{"ok": true}])
	t.eq(delivered.size(), 2, "invalid replies never reach gameplay")
	t.check(bool(net.get("_bad_result_packet_warned")), "incompatible reply is diagnosed once")
	t.current = "network protocol preflight guards all RPCs"
	var other: Node = Net.new()
	var digest: String = NetProtocol.fingerprint(net)
	t.eq(digest.length(), 64, "contract has a SHA-256 fingerprint")
	t.eq(digest, NetProtocol.fingerprint(other), "both endpoint roles share the RPC contract")
	var handshake: PackedByteArray = NetProtocol.auth_payload(net)
	t.check(NetProtocol.accepts(other, handshake), "matching RPC contract is admitted")
	t.check(not NetProtocol.accepts(other, PackedByteArray()), "missing handshake is rejected")
	var changed: PackedByteArray = handshake.duplicate()
	changed[changed.size() - 1] = (changed[changed.size() - 1] + 1) % 256
	t.check(not NetProtocol.accepts(other, changed), "different RPC fingerprint is rejected")
	other.free()
	net.free()
