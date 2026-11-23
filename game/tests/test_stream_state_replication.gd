extends RefCounted
## Regression tests for streaming readiness reports under packet loss and invalid RPCs.

const Replication = preload("res://scripts/shared/stream_state_replication.gd")


func run(t) -> void:
	t.current = "malformed streaming bitsets cannot be decoded or allocated"
	var empty_bits := PackedByteArray()
	t.eq(Replication.decode_cells(Vector2i.ZERO, 1, empty_bits), {},
		"short bitset cannot index past the received payload")
	t.eq(Replication.decode_cells(Vector2i.ZERO, -1, empty_bits), {},
		"negative window radius is rejected")
	t.eq(Replication.encode_cells(Vector2i.ZERO, -1, {}), empty_bits,
		"invalid client window does not allocate an invalid bitset")
	var huge_packet := PackedByteArray()
	huge_packet.resize(Replication.HEADER_BYTES)
	huge_packet.encode_u8(16, 255)
	t.eq(Replication.deserialize(huge_packet), {},
		"wire decoder drops oversized malicious radii before expansion")
	var cells: Dictionary = {Vector2i(-1, 1): true, Vector2i(0, 0): true}
	var encoded: PackedByteArray = Replication.encode_cells(Vector2i.ZERO, 1, cells)
	t.eq(Replication.decode_cells(Vector2i.ZERO, 1, encoded), cells,
		"ordinary compact ready-cell roundtrip remains exact")
	var ordinary_report: Dictionary = {
		"v": 1, "base": 0, "center": Vector2i.ZERO, "radius": 1, "bits": encoded}
	t.eq(Replication.deserialize(Replication.serialize(ordinary_report)), ordinary_report,
		"normal on-wire readiness report survives serialization unchanged")

	t.current = "ACK losses do not cause unbounded streaming memory"
	var client := Replication.Client.new(1)
	client.set_ready(Vector2i.ZERO, true)
	for _i in 100:
		client.build_report(Vector2i.ZERO)
	t.eq(client._pending.size(), 32, "pending versions have a strict memory cap")
	var latest: int = client.version
	client.on_ack(1)
	t.eq(client.acked_version, 0, "evicted ACK has no effect")
	client.on_ack(latest)
	t.eq(client.acked_version, latest, "latest ACK is still usable")
	t.eq(int(client.build_report(Vector2i.ZERO)["base"]), latest,
		"new deltas use the confirmed baseline")

	t.current = "malformed readiness RPCs cannot raise typed read errors"
	var server := Replication.new()
	server.set_client_position("client", Vector2i.ZERO)
	var invalid: Array[Dictionary] = [
		{}, {"bits": PackedByteArray()},
		{"bits": "bad", "center": Vector2i.ZERO, "radius": 1, "v": 1, "base": 0},
		{"bits": PackedByteArray(), "center": "bad", "radius": 1, "v": 1, "base": 0},
		{"bits": PackedByteArray(), "center": Vector2i.ZERO, "radius": "1", "v": 1, "base": 0},
		{"bits": PackedByteArray(), "center": Vector2i.ZERO, "radius": 0, "v": [], "base": 0},
		{"bits": PackedByteArray(), "center": Vector2i.ZERO, "radius": 0, "v": 1, "base": 1},
	]
	for packet in invalid:
		var rejected: Dictionary = server.apply_report("client", packet)
		t.eq(rejected["reason"], "malformed", "invalid report rejected")
		t.eq(server.ack_version("client"), 0, "state unchanged by invalid report")
	t.eq(server.violations("client"), invalid.size(), "violations tracked")

	t.current = "valid full and delta reports remain functional"
	var good := Replication.Client.new(1)
	good.set_ready(Vector2i.ZERO, true)
	var initial: Dictionary = server.apply_report("client", good.build_report(Vector2i.ZERO))
	t.check(bool(initial["ok"]), "full report accepted")
	t.check(server.is_ready("client", Vector2i.ZERO), "initial ready cell replicated")
	good.on_ack(int(initial["ack"]))
	good.set_ready(Vector2i(1, 0), true)
	var updated: Dictionary = server.apply_report("client", good.build_report(Vector2i.ZERO))
	t.check(bool(updated["ok"]), "delta report accepted")
	t.check(server.is_ready("client", Vector2i(1, 0)), "new ready neighbor replicated")
