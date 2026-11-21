extends RefCounted
## Native/stock-Godot parity and 3D audio ray-budget regression.
const Planner = preload("res://scripts/client/audio_occlusion_probes.gd")
const AudioScene = preload("res://scripts/client/audio.gd")


func run(t) -> void:
	t.current = "overdue sources and important combat sounds"
	var due := PackedFloat64Array([0.4, 0.9, 0.0, 1.1])
	var importance := PackedByteArray([0, 3, 1, 3])
	var volume := PackedFloat64Array([-20.0, -20.0, -30.0, 0.0])
	var ids := PackedInt64Array([17, 11, 15, 18])
	t.eq(Planner.select_due(due, importance, volume, ids, 1.0, 2),
		PackedInt32Array([2, 0]), "old overdue checks win, future checks excluded")
	t.eq(Planner.select_due(due, importance, volume, ids, 0.1, 2).size(),
		0, "non-due sources consume no rays")
	t.eq(Planner.select_due(due, importance, volume, ids, 1.0, 0).size(),
		0, "zero ray budget is valid")
	t.eq(Planner.select_due(PackedFloat64Array([1.0, 1.0]),
		PackedByteArray([0, 3]), PackedFloat64Array([-10.0, -80.0]),
		PackedInt64Array([15, 16]), 1.0, 1),
		PackedInt32Array([1]), "priority wins when equally overdue")
	t.eq(Planner.select_due(PackedFloat64Array([1.0, 1.0]),
		PackedByteArray([0, 0]), PackedFloat64Array([-20.0, -20.0]),
		PackedInt64Array([17, 11]), 1.0, 1),
		PackedInt32Array([1]), "unique stable IDs break equal-score ties")

	t.current = "invalid and oversized snapshots fail closed"
	t.eq(Planner.select_due(PackedFloat64Array([0.0]), PackedByteArray([1, 0]),
		PackedFloat64Array([-10.0]), PackedInt64Array([1]), 1.0, 1).size(),
		0, "misaligned arrays fail closed")
	t.eq(Planner.select_due(PackedFloat64Array([0.0]), PackedByteArray([4]),
		PackedFloat64Array([-10.0]), PackedInt64Array([1]), 1.0, 1).size(),
		0, "invalid priority rejected")
	t.eq(Planner.select_due(PackedFloat64Array([0.0]), PackedByteArray([1]),
		PackedFloat64Array([NAN]), PackedInt64Array([1]), 1.0, 1).size(),
		0, "NaN audibility rejected")
	t.eq(Planner.select_due(PackedFloat64Array([0.0, 0.0]), PackedByteArray([1, 1]),
		PackedFloat64Array([-10.0, -20.0]), PackedInt64Array([1, 1]), 1.0, 1).size(),
		0, "duplicate IDs rejected")
	t.eq(Planner.select_due(PackedFloat64Array([0.0]), PackedByteArray([1]),
		PackedFloat64Array([-10.0]), PackedInt64Array([1]), 1.0, 17).size(),
		0, "unbounded rays rejected")

	t.current = "age fairness with three rays for twelve spatial sources"
	var times := PackedFloat64Array()
	var levels := PackedByteArray()
	var db := PackedFloat64Array()
	var stable_ids := PackedInt64Array()
	var counts: Array[int] = []
	for i in 12:
		times.append(0.0)
		levels.append(3 if i < 9 else 0)
		db.append(0.0 if i < 9 else -70.0)
		stable_ids.append(i + 1)
		counts.append(0)
	var native: Object = null
	if ClassDB.class_exists("AudioOcclusionProbePlanner"):
		native = ClassDB.instantiate("AudioOcclusionProbePlanner")
		t.check(native != null and native.has_method("select_due"),
			"custom Cgame registers native audio probe planner")
	for frame in 240:
		var now: float = float(frame) / 30.0
		var scripted: PackedInt32Array = Planner.select_due(times, levels, db, stable_ids, now, 3)
		t.check(scripted.size() <= 3, "hard ray budget frame %d" % frame)
		if native != null:
			t.eq(native.call("select_due", times, levels, db, stable_ids, now, 3),
				scripted, "native/script fair scheduling parity frame %d" % frame)
		for idx in scripted:
			counts[idx] += 1
			times[idx] = now + 0.25
	for i in 12:
		t.check(counts[i] >= 2, "source %d eventually receives a geometry ray" % i)

	t.current = "real Audio node uses the planner and keeps existing ray cap"
	var audio = AudioScene.new()
	t.eq(audio._select_occlusion_probes(
		PackedFloat64Array([0.0, 0.0]), PackedByteArray([0, 2]),
		PackedFloat64Array([-10.0, -40.0]), PackedInt64Array([10, 20]), 1.0, 1),
		PackedInt32Array([1]), "game audio uses portable selector")
	if native != null:
		audio._native_occlusion_probes = native
		t.eq(audio._select_occlusion_probes(
			PackedFloat64Array([0.0, 0.0]), PackedByteArray([0, 2]),
			PackedFloat64Array([-10.0, -40.0]), PackedInt64Array([10, 20]), 1.0, 1),
			PackedInt32Array([1]), "native scheduler selected by game audio")
	var source: String = (AudioScene as Script).source_code
	t.check(source.contains("probe_slots.has(index)") and source.contains("state.intersect_ray(ray)") \
		and source.contains("rays < OBSTRUCTION_RAYS_PER_TICK"),
		"physics checks consume at most three selected ray slots")
	t.check(source.contains("AudioSpatial.smooth_obstruction(old_amount, target, delta)"),
		"unqueued sources still smooth obstruction every physics tick")
	audio.free()
