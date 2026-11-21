extends RefCounted
## MassEntity data-oriented runtime and ORCA crowd avoidance.

const MassEntity = preload("res://scripts/shared/mass_entity.gd")
const CrowdAvoidance = preload("res://scripts/shared/crowd_avoidance.gd")

var _order_log: Array[String] = []


func _world() -> MassEntity:
	var w := MassEntity.new()
	w.define_fragment("pos", TYPE_PACKED_VECTOR3_ARRAY)
	w.define_fragment("vel", TYPE_PACKED_VECTOR3_ARRAY)
	w.define_fragment("hp", TYPE_PACKED_FLOAT32_ARRAY)
	w.define_fragment("tag", TYPE_PACKED_INT32_ARRAY)
	return w


func _move(chunk: Dictionary, count: int, delta: float) -> void:
	for i in count:
		chunk["pos"][i] = chunk["pos"][i] + chunk["vel"][i] * delta


func _log_a(_chunk: Dictionary, _count: int, _delta: float) -> void:
	_order_log.append("a")


func _log_b(_chunk: Dictionary, _count: int, _delta: float) -> void:
	_order_log.append("b")


func _log_c(_chunk: Dictionary, _count: int, _delta: float) -> void:
	_order_log.append("c")


func run(t) -> void:
	t.current = "mass entity lifecycle"
	var w := _world()
	var a := w.create({"pos": Vector3(1, 2, 3), "hp": 10.0})
	var b := w.create({"hp": 20.0, "pos": Vector3(4, 5, 6)})
	var c := w.create({"pos": Vector3.ZERO, "vel": Vector3(1, 0, 0)})
	t.eq(w.entity_count(), 3, "three entities")
	t.eq(w.archetype_count(), 2, "fragment-order independent archetype keys")
	t.check(w.is_alive(a) and w.is_alive(b) and w.is_alive(c), "all alive")
	t.eq(w.get_value(b, "hp"), 20.0, "get float")
	t.eq(w.get_value(a, "pos"), Vector3(1, 2, 3), "get vector")
	w.set_value(a, "hp", 7.5)
	t.eq(w.get_value(a, "hp"), 7.5, "set value")
	t.eq(w.get_value(c, "hp"), null, "missing fragment is null")
	w.destroy(a)
	t.check(not w.is_alive(a), "destroyed id invalid")
	t.eq(w.get_value(b, "pos"), Vector3(4, 5, 6), "swap-remove keeps neighbour data")
	t.eq(w.get_value(a, "hp"), null, "stale id reads nothing")
	var chunks := w.query(PackedStringArray(["hp"]))
	t.eq(chunks.size(), 1, "query hp finds one chunk")
	t.eq(int((chunks[0] as Dictionary)["_count"]), 1, "chunk stays dense after destroy")
	var d := w.create({"pos": Vector3.ONE, "hp": 1.0})
	t.check(d != a, "reused slot gets a new generation")
	t.check(not w.is_alive(a) and w.is_alive(d), "old id stays dead after slot reuse")
	w.destroy(a)
	t.eq(w.entity_count(), 3, "double destroy is a no-op")
	t.eq(w.create({"nope": 1.0}), -1, "undefined fragment rejected")

	t.current = "mass entity queries"
	t.eq(w.query(PackedStringArray(["pos"])).size(), 2, "pos in both archetypes")
	t.eq(w.query(PackedStringArray(["pos", "vel"])).size(), 1, "pos+vel one archetype")
	t.eq(w.query(PackedStringArray(["tag"])).size(), 0, "unused fragment")

	t.current = "mass processors"
	var w2 := _world()
	w2.create({"pos": Vector3.ZERO})
	w2.add_processor("c", PackedStringArray(["pos"]), _log_c, PackedStringArray(["b"]))
	w2.add_processor("b", PackedStringArray(["pos"]), _log_b, PackedStringArray(["a"]))
	w2.add_processor("a", PackedStringArray(["pos"]), _log_a)
	t.eq(",".join(w2.processor_order()), "a,b,c", "topological order")
	_order_log.clear()
	w2.run(0.1)
	t.eq(",".join(PackedStringArray(_order_log)), "a,b,c", "run follows dependencies")

	t.current = "mass 2000 entities"
	var w3 := _world()
	var ids := PackedInt32Array()
	for i in 2000:
		ids.append(w3.create({"pos": Vector3(i, 0, 0), "vel": Vector3(1, 0, 2)}))
	w3.add_processor("move", PackedStringArray(["pos", "vel"]), _move)
	for s in 10:
		w3.run(0.1)
	var p: Vector3 = w3.get_value(ids[1999], "pos")
	t.near(p.x, 2000.0, 0.001, "moved x")
	t.near(p.z, 2.0, 0.001, "moved z")
	for i in range(0, 2000, 2):
		w3.destroy(ids[i])
	t.eq(w3.entity_count(), 1000, "half destroyed")
	w3.run(0.1)
	var q: Vector3 = w3.get_value(ids[1], "pos")
	t.near(q.x, 1.0 + 1.1, 0.001, "survivor still processed after swap-removes")

	t.current = "mass parallel processor"
	var w4 := _world()
	for i in 50:
		w4.create({"pos": Vector3.ZERO, "vel": Vector3(1, 0, 0)})
		w4.create({"pos": Vector3.ZERO, "vel": Vector3(1, 0, 0), "hp": 1.0})
	w4.add_processor("move", PackedStringArray(["pos", "vel"]), _move, PackedStringArray(), true)
	w4.run(1.0)
	var moved := 0
	for ch in w4.query(PackedStringArray(["pos"])):
		var parr: PackedVector3Array = (ch as Dictionary)["pos"]
		for v in parr:
			if is_equal_approx(v.x, 1.0):
				moved += 1
	t.eq(moved, 100, "parallel run covered every chunk")

	t.current = "crowd head-on"
	var radius := 0.5
	var pos := PackedVector2Array([Vector2(-5, 0.2), Vector2(5, -0.2)])
	var vel := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	var goals := PackedVector2Array([Vector2(5, 0.2), Vector2(-5, -0.2)])
	var min_d := 1000.0
	for s in 200:
		var pref := PackedVector2Array()
		for i in 2:
			pref.append((goals[i] - pos[i]).limit_length(1.5))
		vel = CrowdAvoidance.compute_velocities(pos, vel, pref, radius, 1.5, 3.0, 10.0, 10, 0.1)
		for i in 2:
			pos[i] += vel[i] * 0.1
		min_d = minf(min_d, pos[0].distance_to(pos[1]))
	t.check(min_d >= 2.0 * radius * 0.95, "head-on agents keep distance (min %.3f)" % min_d)
	t.check(pos[0].distance_to(goals[0]) < 1.0 and pos[1].distance_to(goals[1]) < 1.0, "head-on agents reach goals")

	t.current = "crowd 200 crossing"
	var run1 := _crossing(t)
	var run2 := _crossing(t)
	t.check(run1[0] >= radius * 2.0 * 0.6, "no deep overlaps (min %.3f)" % run1[0])
	t.check(run1[1], "positions finite")
	t.current = "crowd determinism"
	t.eq(run1[2], run2[2], "identical inputs give identical state")


func _crossing(t) -> Array:
	var n := 200
	var radius := 0.5
	var pos := PackedVector2Array()
	var goals := PackedVector2Array()
	var vel := PackedVector2Array()
	for i in n:
		# Two opposing 10x10 blocks swapping sides through each other.
		var col := (i % 100) % 10
		var row := int((i % 100) / 10)
		var east := i < 100
		var x := -20.0 + col * 1.4
		var y := -6.3 + row * 1.4 + (0.1 if east else -0.1)
		pos.append(Vector2(x if east else -x, y))
		goals.append(Vector2(-x if east else x, y))
		vel.append(Vector2.ZERO)
	var min_d := 1000.0
	var finite := true
	for s in 260:
		var pref := PackedVector2Array()
		for i in n:
			pref.append((goals[i] - pos[i]).limit_length(1.4))
		vel = CrowdAvoidance.compute_velocities(pos, vel, pref, radius, 1.4, 5.0, 6.0, 16, 0.1)
		for i in n:
			pos[i] += vel[i] * 0.1
			if not is_finite(pos[i].x) or not is_finite(pos[i].y):
				finite = false
		if s % 4 == 0:
			for i in n:
				for j in range(i + 1, n):
					var dd := pos[i].distance_squared_to(pos[j])
					if dd < min_d * min_d:
						min_d = sqrt(dd)
	var sum := 0.0
	for i in n:
		sum += pos[i].x * 3.1 + pos[i].y
	return [min_d, finite, sum]
