extends RefCounted
## Replication graph, net schema and quantization profile.

const ReplicationGraph = preload("res://scripts/shared/replication_graph.gd")
const NetSchema = preload("res://scripts/shared/net_schema.gd")
const QuantizationProfile = preload("res://scripts/shared/quantization_profile.gd")


func _ids(list: Array) -> Array:
	var out: Array = []
	for e in list:
		var d: Dictionary = e
		out.append(int(d["id"]))
	out.sort()
	return out


func _conn(id: int, pos: Vector3, radius: float = 100.0, bytes: int = 100000) -> Dictionary:
	return {"id": id, "position": pos, "view_radius": radius, "bandwidth_bytes": bytes}


func run(t) -> void:
	t.current = "graph relevance"
	var g := ReplicationGraph.new()
	g.set_class_config("npc", 1.0, 0.0, 20)
	g.add_entity(1, "npc", Vector3(10, 0, 10))
	g.add_entity(2, "npc", Vector3(500, 0, 500))
	g.add_entity(3, "npc", Vector3(900, 0, 900), -1, true)
	g.add_entity(4, "npc", Vector3(900, 0, 0), 7, false, true)
	t.eq(_ids(g.gather_for(_conn(7, Vector3.ZERO))), [1, 3, 4], "near + always + own owner-only")
	t.eq(_ids(g.gather_for(_conn(8, Vector3.ZERO))), [1, 3], "other connection misses owner-only")
	g.set_position(2, Vector3(20, 0, 20))
	t.check(_ids(g.gather_for(_conn(8, Vector3.ZERO))).has(2), "moved entity enters view")

	t.current = "graph owner-only precedence and entity lifetimes"
	var private_graph := ReplicationGraph.new()
	private_graph.set_class_config("private", 1.0, 60.0, 10)
	private_graph.add_entity(10, "private", Vector3.ZERO, 7, true, true)
	t.eq(_ids(private_graph.gather_for(_conn(8, Vector3.ZERO))), [],
			"owner-only takes precedence over always-relevant even at close range")
	t.eq(_ids(private_graph.gather_for(_conn(7, Vector3(1000, 0, 1000)))), [10],
			"the owner receives private entities outside the spatial radius")
	t.eq(private_graph.gather_for(_conn(7, Vector3.ZERO)).size(), 0,
			"the active incarnation respects its send interval")
	private_graph.remove_entity(10)
	private_graph.add_entity(10, "private", Vector3.ZERO)
	t.eq(_ids(private_graph.gather_for(_conn(7, Vector3.ZERO))), [10],
			"a reused ID is immediately eligible and does not inherit its old timer")
	t.eq(_ids(private_graph.gather_for(_conn(8, Vector3.ZERO))), [10],
			"reusing an ID clears its previous private flags")
	private_graph.remove_entity(10)
	t.eq(private_graph.gather_for(_conn(8, Vector3.ZERO)).size(), 0,
			"removed special IDs never leave stale candidates")

	t.current = "graph sparse view and runtime cell size"
	var sparse_graph := ReplicationGraph.new()
	sparse_graph.add_entity(1, "npc", Vector3(-180, 0, 240))
	sparse_graph.add_entity(2, "npc", Vector3(180, 0, 240))
	sparse_graph.add_entity(3, "npc", Vector3(500000, 0, 0))
	sparse_graph.add_entity(4, "npc", Vector3(0, 0, 0), 2, false, true)
	t.eq(_ids(sparse_graph.gather_for(_conn(1, Vector3.ZERO, 100000.0))), [1, 2],
			"huge sparse query retains exact distance and owner filtering")
	sparse_graph.cell_size = 16.0
	t.eq(_ids(sparse_graph.gather_for(_conn(1, Vector3(-180, 0, 240), 5.0))), [1],
			"changing grid cell size rebuilds existing spatial buckets")
	sparse_graph.cell_size = 0.0
	t.eq(sparse_graph.cell_size, 16.0, "invalid cell size is rejected")
	sparse_graph.set_position(1, Vector3(50, 0, 50))
	t.eq(_ids(sparse_graph.gather_for(_conn(1, Vector3(50, 0, 50), 5.0))), [1],
			"movement after cell resize updates the rebuilt grid")

	t.current = "graph dormancy"
	var d := ReplicationGraph.new()
	d.set_class_config("door", 1.0, 0.0, 10)
	d.add_entity(1, "door", Vector3(5, 0, 5))
	d.set_dormant(1, true)
	t.eq(d.gather_for(_conn(1, Vector3.ZERO)).size(), 0, "dormant skipped")
	d.wake(1)
	t.eq(d.gather_for(_conn(1, Vector3.ZERO)).size(), 1, "woken entity replicates")
	d.set_dormant(1, true)
	t.eq(d.gather_for(_conn(1, Vector3.ZERO)).size(), 0, "dormant again after the wake was consumed")

	t.current = "graph frequency"
	var f := ReplicationGraph.new()
	f.set_class_config("slow", 1.0, 1.0, 10)
	f.add_entity(1, "slow", Vector3(1, 0, 1))
	t.eq(f.gather_for(_conn(1, Vector3.ZERO)).size(), 1, "first send")
	f.advance(0.4)
	t.eq(f.gather_for(_conn(1, Vector3.ZERO)).size(), 0, "throttled within interval")
	f.advance(0.7)
	t.eq(f.gather_for(_conn(1, Vector3.ZERO)).size(), 1, "due after interval")

	t.current = "graph bandwidth + starvation"
	var b := ReplicationGraph.new()
	b.set_class_config("hi", 3.0, 0.0, 50)
	b.set_class_config("lo", 1.0, 0.0, 50)
	b.add_entity(1, "hi", Vector3(1, 0, 1), -1, true)
	b.add_entity(2, "lo", Vector3(2, 0, 2), -1, true)
	var first: Array = b.gather_for(_conn(1, Vector3.ZERO, 100.0, 50))
	t.eq(first.size(), 1, "budget limits to one entity")
	var fd: Dictionary = first[0]
	t.eq(int(fd["id"]), 1, "highest priority wins")
	var low_sent: bool = false
	for i in 6:
		for e in b.gather_for(_conn(1, Vector3.ZERO, 100.0, 50)):
			var ed: Dictionary = e
			if int(ed["id"]) == 2:
				low_sent = true
	t.check(low_sent, "starved low-priority entity eventually sent")

	t.current = "schema generation"
	var sample: Dictionary = {"alive": true, "hp": 100, "speed": 1.5, "pos": Vector3.ZERO, "rot": Quaternion.IDENTITY, "name": "x"}
	var schema: Dictionary = NetSchema.generate_from_sample(sample, {"hp": {"min": 0, "max": 255, "condition": "owner_only"}})
	var types: Dictionary = {}
	var sf: Array = schema["fields"]
	for fl in sf:
		var fld: Dictionary = fl
		types[fld["name"]] = fld["type"]
	t.eq(types["alive"], "bool", "bool inferred")
	t.eq(types["hp"], "int", "int inferred")
	t.eq(types["speed"], "float", "float inferred")
	t.eq(types["pos"], "vec3", "vec3 inferred")
	t.eq(types["rot"], "quat", "quat inferred")
	t.eq(types["name"], "string", "string inferred")
	var hp_field: Dictionary = {}
	for fl2 in sf:
		var f2: Dictionary = fl2
		if f2["name"] == "hp":
			hp_field = f2
	t.eq(int(hp_field["bits"]), 8, "hint range gives 8 bits")
	t.eq(hp_field["condition"], "owner_only", "hint sets condition")

	t.current = "schema serialization"
	var state: Dictionary = {"alive": true, "hp": 77, "speed": 12.34, "pos": Vector3(10.5, -3.25, 200.0), "rot": Quaternion(Vector3.UP, 1.0), "name": "bob"}
	var bytes: PackedByteArray = NetSchema.serialize(schema, state, {}, true)
	var back: Dictionary = NetSchema.deserialize(schema, bytes, {})
	t.eq(back["alive"], true, "bool round trip")
	t.eq(back["hp"], 77, "int round trip exact")
	t.eq(back["name"], "bob", "string round trip")
	t.near(float(back["speed"]), 12.34, 0.02, "float within quantization error")
	var pb: Vector3 = back["pos"]
	t.check(pb.distance_to(Vector3(10.5, -3.25, 200.0)) < 0.1, "vec3 within quantization error")
	var qb: Quaternion = back["rot"]
	t.check(qb.angle_to(Quaternion(Vector3.UP, 1.0)) < 0.01, "quat within quantization error")

	var moved: Dictionary = state.duplicate()
	moved["speed"] = 20.0
	var delta: PackedByteArray = NetSchema.serialize(schema, moved, back, true)
	t.check(delta.size() < bytes.size(), "changed-only payload smaller")
	var applied: Dictionary = NetSchema.deserialize(schema, delta, back)
	t.near(float(applied["speed"]), 20.0, 0.02, "delta applies changed field")
	t.eq(applied["name"], "bob", "delta keeps unchanged field")

	var other: Dictionary = NetSchema.deserialize(schema, NetSchema.serialize(schema, state, {}, false), {})
	t.check(not other.has("hp"), "owner-only field hidden from non-owner")
	t.check(other.has("speed"), "public field visible to non-owner")

	t.current = "schema versioning"
	var vb: PackedByteArray = NetSchema.serialize_versioned(schema, state, {}, true)
	t.check(bool(NetSchema.deserialize_versioned(schema, vb, {})["ok"]), "matching hash accepted")
	var schema2: Dictionary = NetSchema.generate_from_sample(sample.merged({"extra": 1}))
	t.check(NetSchema.schema_hash(schema) != NetSchema.schema_hash(schema2), "different schemas hash differently")
	t.check(not bool(NetSchema.deserialize_versioned(schema2, vb, {})["ok"]), "hash mismatch rejected")

	t.current = "quantization profile"
	var prof := QuantizationProfile.new()
	prof.from_schema(schema)
	var e16: float = prof.max_error("speed")
	t.near(e16, 2048.0 / 65535.0 * 0.5, 0.0001, "error bound at 16 bits")
	var need: int = prof.suggest_bits("speed", 0.05)
	prof.set_bits("speed", need)
	t.check(prof.max_error("speed") <= 0.05, "suggested bits meet target error")
	t.check(need > 1 and prof.max_error("speed") * 1.5 > 0.0 and (need == 1 or QuantizationProfile.new().max_error_for(2048.0, need - 1) > 0.05), "suggestion is minimal")
	t.check(prof.total_bits() > 0 and prof.bandwidth_bytes_per_sec(20.0, 10) > 0.0, "bandwidth estimate")
	var json: String = prof.to_json()
	var prof2 := QuantizationProfile.new()
	t.check(prof2.from_json(json), "json imports")
	t.eq(prof2.total_bits(), prof.total_bits(), "json round trip keeps bits")
