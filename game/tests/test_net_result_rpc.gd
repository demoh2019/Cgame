extends RefCounted
## Verify current RPC replies, older single-argument envelopes, and safe
## handling of malformed replies without guessing command outcomes.

const Net = preload("res://scripts/shared/net.gd")
const NetProtocol = preload("res://scripts/shared/net_protocol.gd")
const NetSchema = preload("res://scripts/shared/net_schema.gd")


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
	t.current = "network bitstream rejects truncated packets and preserves Unicode names"
	var schema: Dictionary = {"fields": [
		NetSchema.make_field("name", "string", 8),
		NetSchema.make_field("count", "int", 12, 0.0, 4095.0),
	]}
	var long_name: String = "Ж".repeat(200)
	var packet: PackedByteArray = NetSchema.serialize(schema,
		{"name": long_name, "count": 1729}, {}, true)
	var decoded: Dictionary = NetSchema.deserialize(schema, packet, {})
	t.eq(decoded.get("name"), "Ж".repeat(127),
		"255-byte string limit never splits a multibyte UTF-8 character")
	t.eq(int(decoded.get("count", -1)), 1729,
		"field following a multibyte name retains its correct bit offset")
	var partial: PackedByteArray = packet.duplicate()
	partial.resize(partial.size() - 1)
	t.eq(NetSchema.deserialize(schema, partial, {"count": 2}), {},
		"a truncated value cannot silently replace a valid baseline")
	t.eq(NetSchema.deserialize(schema, PackedByteArray(), {"count": 2}), {},
		"a missing presence mask cannot silently masquerade as an empty delta")
	var baseline: Dictionary = {"name": "prior", "count": 15}
	var empty_delta: PackedByteArray = NetSchema.serialize(schema, {}, baseline, true)
	t.eq(NetSchema.deserialize(schema, empty_delta, baseline), baseline,
		"valid unchanged deltas still preserve their baseline")

	t.current = "versioned snapshots reject incomplete payloads and preserve valid deltas"
	var versioned: PackedByteArray = NetSchema.serialize_versioned(schema,
		{"name": "Aurora", "count": 1729}, {}, true)
	var versioned_ok: Dictionary = NetSchema.deserialize_versioned(schema, versioned, {})
	t.check(bool(versioned_ok["ok"]), "matching versioned snapshot is valid")
	t.eq(versioned_ok["state"], {"name": "Aurora", "count": 1729},
		"versioned decode restores all acknowledged values")
	var truncated: PackedByteArray = versioned.duplicate()
	truncated.resize(truncated.size() - 1)
	var invalid: Dictionary = NetSchema.deserialize_versioned(schema, truncated, {"count": 2})
	t.check(not bool(invalid["ok"]) and (invalid["state"] as Dictionary).is_empty(),
		"matching hash cannot conceal a truncated versioned snapshot")
	var header_only: PackedByteArray = versioned.slice(0, 4)
	t.check(not bool(NetSchema.deserialize_versioned(schema, header_only, {})["ok"]),
		"header without a presence mask is never accepted")
	var wrong_header: PackedByteArray = versioned.duplicate()
	wrong_header[0] = (wrong_header[0] + 1) % 256
	t.check(not bool(NetSchema.deserialize_versioned(schema, wrong_header, {})["ok"]),
		"mismatched schema fingerprints are still refused")
	var valid_empty: PackedByteArray = NetSchema.serialize_versioned(schema, {}, baseline, true)
	t.eq(NetSchema.deserialize_versioned(schema, valid_empty, baseline),
		{"ok": true, "state": baseline},
		"valid empty delta retains its prior state without a false corruption warning")

	other.free()
	net.free()
