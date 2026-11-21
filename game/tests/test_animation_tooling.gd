extends RefCounted
## Animation tooling: pose search debugger, motion matching profiler/optimiser/auto builder,
## facial mocap + rig data, constraint graph.

const MotionMatching = preload("res://scripts/client/motion_matching.gd")
const MotionDBBuilder = preload("res://scripts/client/motion_db_builder.gd")
const PoseSearchDebugger = preload("res://scripts/client/pose_search_debugger.gd")
const MMTools = preload("res://scripts/client/motion_matching_tools.gd")
const FacialMocap = preload("res://scripts/client/facial_mocap.gd")
const FacialRigData = preload("res://scripts/client/facial_rig_data.gd")
const ConstraintGraph = preload("res://scripts/client/constraint_graph.gd")


func _query(db: MotionMatching, vy: float, vx: float, noise: RandomNumberGenerator, foot_noise: float) -> Dictionary:
	var v := Vector2(vx, vy)
	var q: Dictionary = db.query_from(v, 0.0, v, 0.0, Vector3(-0.1, 0.0, 0.0), Vector3(0.1, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO)
	var f: PackedFloat32Array = q["features"]
	for d in range(12, 24):
		f[d] += noise.randfn(0.0, foot_noise)
	q["features"] = f
	return q


# ---- Synthetic 68-point face (inter-ocular distance 1, y down) ----

func _neutral_face() -> PackedVector2Array:
	var p := PackedVector2Array()
	p.resize(68)
	for i in 17:
		var u: float = (float(i) - 8.0) / 8.0
		p[i] = Vector2(0.62 * u, 1.35 - 1.25 * u * u)
	var brow_x: Array[float] = [-0.55, -0.45, -0.35, -0.27, -0.15]
	var brow_y: Array[float] = [-0.3, -0.35, -0.37, -0.35, -0.3]
	for k in 5:
		p[17 + k] = Vector2(brow_x[k], brow_y[k])
		p[26 - k] = Vector2(-brow_x[k], brow_y[k])
	p[27] = Vector2(0.0, 0.0)
	p[28] = Vector2(0.0, 0.15)
	p[29] = Vector2(0.0, 0.3)
	p[30] = Vector2(0.0, 0.45)
	p[31] = Vector2(-0.12, 0.55)
	p[32] = Vector2(-0.06, 0.58)
	p[33] = Vector2(0.0, 0.6)
	p[34] = Vector2(0.06, 0.58)
	p[35] = Vector2(0.12, 0.55)
	# right eye (image left)
	p[36] = Vector2(-0.5, 0.0)
	p[37] = Vector2(-0.4, -0.06)
	p[38] = Vector2(-0.3, -0.06)
	p[39] = Vector2(-0.2, 0.0)
	p[40] = Vector2(-0.3, 0.06)
	p[41] = Vector2(-0.4, 0.06)
	p[42] = Vector2(0.2, 0.0)
	p[43] = Vector2(0.3, -0.06)
	p[44] = Vector2(0.4, -0.06)
	p[45] = Vector2(0.5, 0.0)
	p[46] = Vector2(0.4, 0.06)
	p[47] = Vector2(0.3, 0.06)
	var outer: Array[Vector2] = [Vector2(-0.28, 0.9), Vector2(-0.18, 0.84), Vector2(-0.08, 0.82), Vector2(0.0, 0.83),
		Vector2(0.08, 0.82), Vector2(0.18, 0.84), Vector2(0.28, 0.9), Vector2(0.18, 0.96), Vector2(0.08, 0.98),
		Vector2(0.0, 0.99), Vector2(-0.08, 0.98), Vector2(-0.18, 0.96)]
	for k in 12:
		p[48 + k] = outer[k]
	var inner: Array[Vector2] = [Vector2(-0.2, 0.9), Vector2(-0.1, 0.87), Vector2(0.0, 0.87), Vector2(0.1, 0.87),
		Vector2(0.2, 0.9), Vector2(0.1, 0.93), Vector2(0.0, 0.93), Vector2(-0.1, 0.93)]
	for k in 8:
		p[60 + k] = inner[k]
	return p


func _shift(p: PackedVector2Array, ids: Array, d: Vector2) -> PackedVector2Array:
	var o := p.duplicate()
	for i in ids:
		o[int(i)] += d
	return o


func _place(p: PackedVector2Array, scale: float, roll: float, off: Vector2) -> PackedVector2Array:
	var o := PackedVector2Array()
	for v in p:
		o.append(v.rotated(roll) * scale + off)
	return o


func _smile(p: PackedVector2Array) -> PackedVector2Array:
	var o := _shift(p, [48, 60], Vector2(-0.04, -0.08))
	return _shift(o, [54, 64], Vector2(0.04, -0.08))


func _brow_raise(p: PackedVector2Array) -> PackedVector2Array:
	var ids: Array = []
	for i in range(17, 27):
		ids.append(i)
	return _shift(p, ids, Vector2(0.0, -0.12))


func _jaw_open(p: PackedVector2Array) -> PackedVector2Array:
	var o := _shift(p, [5, 6, 7, 8, 9, 10, 11, 56, 57, 58, 65, 66, 67], Vector2(0.0, 0.3))
	return _shift(o, [48, 54, 55, 59, 60, 64], Vector2(0.0, 0.15))


func _blink(p: PackedVector2Array) -> PackedVector2Array:
	var o := _shift(p, [37, 38, 43, 44], Vector2(0.0, 0.05))
	return _shift(o, [40, 41, 46, 47], Vector2(0.0, -0.05))


func run(t) -> void:
	t.current = "pose search debugger"
	var db := MotionDBBuilder.build_default_database()
	var dbg := PoseSearchDebugger.new()
	dbg.top_n = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var q: Dictionary = _query(db, 1.4, 0.0, rng, 0.0)
	var rec: Dictionary = dbg.record_search(db, q)
	var cands: Array = rec["candidates"]
	t.eq(cands.size(), 4, "top-N candidates recorded")
	var chosen: Dictionary = rec["chosen"]
	var c0: Dictionary = cands[0]
	t.eq(c0["clip"], chosen["clip"], "best candidate is the chosen clip")
	t.near(float(c0["cost"]), float(chosen["cost"]), 0.0001, "best candidate cost matches runtime search")
	var sorted_ok: bool = true
	var sums_ok: bool = true
	var prev: float = -1.0
	for c in cands:
		var cd: Dictionary = c
		var cost: float = cd["cost"]
		if cost < prev:
			sorted_ok = false
		prev = cost
		var br: Dictionary = cd["breakdown"]
		var s: float = 0.0
		for g in PoseSearchDebugger.GROUPS:
			s += float(br[g])
		if absf(s - cost * cost) > 0.0001:
			sums_ok = false
	t.check(sorted_ok, "candidates sorted by cost")
	t.check(sums_ok, "breakdown sums to cost squared")
	t.eq(dbg.records.size(), 1, "record stored")
	t.eq((rec["query_features"] as PackedFloat32Array).size(), MotionMatching.DIMS, "query features recorded")
	t.check(PoseSearchDebugger.GROUPS.has(PoseSearchDebugger.dominant_group(c0)), "dominant group is a known group")
	var tagged: Dictionary = dbg.record_search(db, q, "", -1, PackedStringArray(["run"]))
	t.eq((tagged["chosen"] as Dictionary)["clip"], "run_forward", "tag filter honoured")
	t.check(PoseSearchDebugger.format_record(rec).contains("chosen"), "format_record text")
	dbg.max_records = 3
	for _i in 5:
		dbg.record_search(db, q)
	t.check(dbg.records.size() <= 3, "ring buffer bounded")

	t.current = "motion matching profiler"
	var qs: Array = []
	for k in 40:
		qs.append(_query(db, 0.2 + 0.1 * float(k), 0.0, rng, 0.0))
	var prof: Dictionary = MMTools.profile(db, qs)
	t.eq(prof["queries"], 40, "profiled all queries")
	t.check(float(prof["search_us_avg"]) > 0.0 and float(prof["search_us_max"]) >= float(prof["search_us_avg"]), "timing stats ordered")
	t.check(float(prof["pruned_bucket_pct"]) >= 0.0 and float(prof["pruned_bucket_pct"]) <= 100.0, "pruned percentage in range")
	t.check(float(prof["cost_min"]) <= float(prof["cost_p50"]) and float(prof["cost_p50"]) <= float(prof["cost_max"]), "cost percentiles ordered")
	var hist_total: int = 0
	for h in prof["cost_histogram"] as PackedInt32Array:
		hist_total += h
	t.eq(hist_total, 40, "histogram counts every query")

	t.current = "weight optimiser"
	var odb := MotionMatching.new()
	odb.weights = {"velocity": 1.0, "facing": 0.5, "traj_pos": 1.0, "traj_facing": 0.5, "foot_pos": 8.0, "foot_vel": 8.0}
	for cl in MotionDBBuilder.synthesize_locomotion_clips():
		var cdict: Dictionary = cl
		odb.add_clip(String(cdict["name"]), cdict["frames"], 30.0, true, cdict["tags"])
	odb.build()
	var nrng := RandomNumberGenerator.new()
	nrng.seed = 11
	var val: Array = []
	for k in 60:
		var vy: float = 1.0 + 3.0 * float(k) / 60.0
		val.append(_query(odb, vy, 0.0, nrng, 1.5))
	var base_j: float = MMTools.jitter(odb, val)
	var opt: Dictionary = MMTools.optimize_weights(odb, val, 2, false)
	t.near(float(opt["before"]), base_j, 0.0001, "optimiser starts from current jitter")
	t.check(float(opt["after"]) < float(opt["before"]), "optimiser reduces jitter (%f -> %f)" % [float(opt["before"]), float(opt["after"])])
	var new_w: Dictionary = opt["weights"]
	t.check(float(new_w["foot_pos"]) / maxf(float(new_w["velocity"]), 0.0001) < 8.0 or float(new_w["foot_vel"]) / maxf(float(new_w["velocity"]), 0.0001) < 8.0, "noisy foot weights lowered relative to velocity (%s)" % str(new_w))
	t.near(float(odb.weights["foot_pos"]), 8.0, 0.0001, "source db untouched without apply")
	var check_db: MotionMatching = MMTools.clone_with_weights(odb, new_w)
	t.near(MMTools.jitter(check_db, val), float(opt["after"]), 0.0001, "reported jitter reproducible")

	t.current = "auto builder"
	var clips: Array = MotionDBBuilder.synthesize_locomotion_clips()
	var raw_clips: Array = []
	for cl2 in clips:
		var c2: Dictionary = (cl2 as Dictionary).duplicate()
		c2["tags"] = PackedStringArray()
		raw_clips.append(c2)
	var built: Dictionary = MMTools.auto_build(raw_clips, true)
	var tag_map: Dictionary = built["tags"]
	t.check((tag_map["idle"] as PackedStringArray).has("idle"), "idle tagged")
	t.check((tag_map["run_forward"] as PackedStringArray).has("run"), "run tagged")
	t.check((tag_map["walk_forward"] as PackedStringArray).has("walk"), "walk tagged")
	t.check((tag_map["walk_back"] as PackedStringArray).has("backward"), "backward tagged")
	t.check((tag_map["strafe_left"] as PackedStringArray).has("strafe"), "strafe tagged")
	t.check((tag_map["turn_left"] as PackedStringArray).has("turn"), "turn tagged")
	var bdb: MotionMatching = built["db"]
	t.eq(bdb.clip_names.size(), raw_clips.size(), "all clips built")
	var res: Dictionary = bdb.search(_query(bdb, 4.0, 0.0, nrng, 0.0), "", -1, PackedStringArray(["run"]))
	t.eq(res["clip"], "run_forward", "auto tags usable as search filter")
	var pruned_build: Dictionary = MMTools.auto_build(raw_clips, true, 0.2)
	t.check(int(pruned_build["pruned"]) > 0, "pruning removes redundant frames")

	t.current = "facial mocap neutral"
	var neutral: PackedVector2Array = _neutral_face()
	var mocap := FacialMocap.new()
	mocap.smoothing_enabled = false
	t.check(mocap.calibrate_frame(_place(neutral, 120.0, 0.3, Vector2(300.0, 200.0))), "calibration accepted")
	var zero: Dictionary = mocap.process(_place(neutral, 120.0, 0.3, Vector2(300.0, 200.0)))
	var all_zero: bool = true
	for k in zero["aus"] as Dictionary:
		if absf(float((zero["aus"] as Dictionary)[k])) > 0.0001:
			all_zero = false
	t.check(all_zero, "neutral frame gives zero AUs")
	var zbs: Dictionary = zero["blendshapes"]
	var zero_bs: bool = true
	for k in zbs:
		if float(zbs[k]) > 0.0001:
			zero_bs = false
	t.check(zero_bs, "neutral frame gives zero blend shapes")
	t.near(float(zero["head_roll"]), 0.3, 0.001, "head roll recovered")
	t.check(not mocap.calibrate([]), "empty calibration rejected")
	t.check(mocap.solve_aus(PackedVector2Array()).is_empty(), "short landmark array rejected")

	t.current = "facial mocap expressions"
	var cam := func(p: PackedVector2Array) -> PackedVector2Array: return _place(p, 80.0, -0.2, Vector2(100.0, 50.0))
	mocap.calibrate_frame(cam.call(neutral))
	var sm: Dictionary = mocap.process(cam.call(_smile(neutral)))
	var sa: Dictionary = sm["aus"]
	t.check(float(sa["AU12_L"]) > 0.5 and float(sa["AU12_R"]) > 0.5, "smile activates AU12")
	t.check(float(sa["AU26"]) < 0.05 and float(sa["AU1"]) < 0.05, "smile leaves jaw and brows alone")
	t.check(float(sa["AU12_L"]) > float(sa["AU20"]), "smile is not a lip stretch")
	var sbs: Dictionary = sm["blendshapes"]
	t.check(float(sbs["mouthSmileLeft"]) > 0.5 and float(sbs["mouthSmileRight"]) > 0.5, "smile drives mouthSmile blend shapes")
	var br: Dictionary = mocap.process(cam.call(_brow_raise(neutral)))
	var ba: Dictionary = br["aus"]
	t.check(float(ba["AU1"]) > 0.8 and float(ba["AU2_L"]) > 0.8 and float(ba["AU2_R"]) > 0.8, "brow raise activates AU1/AU2")
	t.check(float(ba["AU4_L"]) < 0.01 and float(ba["AU12_L"]) < 0.05, "brow raise does not frown or smile")
	t.check(float((br["blendshapes"] as Dictionary)["browInnerUp"]) > 0.8, "brow raise drives browInnerUp")
	var jo: Dictionary = mocap.process(cam.call(_jaw_open(neutral)))
	var ja: Dictionary = jo["aus"]
	t.check(float(ja["AU26"]) > 0.8, "jaw open activates AU26")
	t.check(float(ja["AU25"]) > 0.8, "jaw open parts the lips (AU25)")
	t.check(float(ja["AU15_L"]) < 0.05 and float(ja["AU12_L"]) < 0.05, "jaw open does not read as frown or smile")
	t.check(float((jo["blendshapes"] as Dictionary)["jawOpen"]) > 0.8, "jaw open drives jawOpen")
	var bl: Dictionary = mocap.process(cam.call(_blink(neutral)))
	t.check(float((bl["aus"] as Dictionary)["AU45_L"]) > 0.8, "blink activates AU45")
	var fr: Dictionary = mocap.process(cam.call(_shift(neutral, [48, 60], Vector2(0.0, 0.08))))
	t.check(float((fr["aus"] as Dictionary)["AU15_R"]) > 0.5 and float((fr["aus"] as Dictionary)["AU15_L"]) < 0.05, "one-sided frown is one-sided")

	t.current = "facial mocap smoothing"
	var sm_m := FacialMocap.new()
	sm_m.calibrate_frame(neutral)
	var raw_dev: float = 0.0
	var sm_dev: float = 0.0
	var smiling: PackedVector2Array = _smile(neutral)
	var wob := RandomNumberGenerator.new()
	wob.seed = 3
	var last_v: float = 0.0
	var half_frame: PackedVector2Array = neutral.duplicate()
	for i in 68:
		half_frame[i] = neutral[i].lerp(smiling[i], 0.5)
	var mean_au: float = float(sm_m.solve_aus(half_frame)["AU12_L"])
	for k in 90:
		var amt: float = 0.5 + (0.3 if k % 2 == 0 else -0.3)
		var frame: PackedVector2Array = neutral.duplicate()
		for i in 68:
			frame[i] = neutral[i].lerp(smiling[i], amt)
		var rawv: float = float(sm_m.solve_aus(frame)["AU12_L"])
		last_v = float((sm_m.process(frame, 1.0 / 30.0)["aus"] as Dictionary)["AU12_L"])
		if k >= 30:
			raw_dev += absf(rawv - mean_au)
			sm_dev += absf(last_v - mean_au)
	t.check(sm_dev < raw_dev * 0.6, "One Euro smoothing damps jitter (%f vs %f)" % [sm_dev, raw_dev])
	sm_m.reset_filters()
	var step_val: float = 0.0
	for k in 60:
		step_val = float((sm_m.process(smiling, 1.0 / 30.0)["aus"] as Dictionary)["AU12_L"])
	t.near(step_val, float(sm_m.solve_aus(smiling)["AU12_L"]), 0.02, "smoothed value converges to a steady input")

	t.current = "facial rig data"
	var rig: RefCounted = FacialRigData.default_rig()
	t.eq((rig.blendshapes as Array).size(), 52, "52 ARKit shapes")
	t.eq((rig.validate() as Array).size(), 0, "default rig valid")
	t.check((rig.symmetry_pairs() as Array).size() >= 20, "symmetry pairs found")
	t.eq((rig.asymmetric_shapes() as Array).size(), 0, "default rig symmetric")
	t.eq(FacialRigData.mirror_name("mouthSmileLeft"), "mouthSmileRight", "mirror shape name")
	t.eq(FacialRigData.mirror_name("AU12_R"), "AU12_L", "mirror AU key")
	t.eq(FacialRigData.mirror_name("jawOpen"), "jawOpen", "centre shape unchanged")
	(rig.au_map as Dictionary).erase("AU12_R")
	t.eq(rig.symmetrize(true) >= 1, true, "symmetrize wrote mappings")
	var mir: Dictionary = (rig.au_map as Dictionary)["AU12_R"]
	t.check(mir.has("mouthSmileRight") and not mir.has("mouthSmileLeft"), "mirrored mapping uses right shape")
	t.check(rig.set_mapping("AU6", "cheekSquintLeft", 0.7), "set_mapping on known shape")
	t.check(not rig.set_mapping("AU6", "noSuchShape", 1.0), "unknown shape refused")
	var bw: Dictionary = rig.blend({"AU6": 1.0, "AU12_L": 2.0})
	t.near(float(bw["cheekSquintLeft"]), 0.7, 0.0001, "blend applies weight")
	t.near(float(bw["mouthSmileLeft"]), 1.0, 0.0001, "blend clamps to 1")
	var path: String = "user://test_facial_rig_%d.json" % Time.get_ticks_usec()
	rig.rig_name = "roundtrip"
	t.check(rig.save_json(path), "rig saved")
	var loaded: RefCounted = FacialRigData.new()
	t.check(loaded.load_json(path), "rig loaded")
	t.eq(loaded.rig_name, "roundtrip", "name round trips")
	t.eq((loaded.blendshapes as Array).size(), 52, "shapes round trip")
	t.eq(loaded.au_map, rig.au_map, "AU mappings round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	t.check(not FileAccess.file_exists(path), "temp rig file deleted")
	t.check(not loaded.load_json("user://missing_rig_file.json"), "missing file fails cleanly")
	t.check(rig.remove_blendshape("jawOpen") and not (rig.au_map as Dictionary).has("AU26"), "removing a shape prunes its mappings")

	t.current = "constraint graph"
	var pose: Dictionary = ConstraintGraph.make_pose(PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0)]))
	var g := ConstraintGraph.new()
	g.add({"type": "two_bone", "root": 0, "mid": 1, "tip": 2, "target": [1.0, 1.0, 0.0], "pole": [0.0, 0.0, 1.0]})
	var res_pose: Dictionary = g.evaluate(pose)
	var rp: PackedVector3Array = res_pose["positions"]
	t.near(rp[2].distance_to(Vector3(1.0, 1.0, 0.0)), 0.0, 0.001, "two-bone reaches reachable target")
	t.near(rp[0].distance_to(rp[1]), 1.0, 0.001, "upper bone length preserved")
	t.near(rp[1].distance_to(rp[2]), 1.0, 0.001, "lower bone length preserved")
	t.check(rp[1].z > 0.0, "elbow bends toward the pole")
	t.near((pose["positions"] as PackedVector3Array)[2].x, 2.0, 0.0001, "input pose not mutated")
	g.clear()
	g.add({"type": "two_bone", "root": 0, "mid": 1, "tip": 2, "target": [0.0, 5.0, 0.0], "pole": [0.0, 0.0, 1.0], "weight": 1.0})
	var far: PackedVector3Array = g.evaluate(pose)["positions"]
	t.near(far[2].distance_to(Vector3(0.0, 2.0, 0.0)), 0.0, 0.001, "unreachable target gives straight limb")
	# aim
	g.clear()
	g.add({"type": "aim", "bone": 3, "forward": [0.0, 0.0, -1.0], "target": [5.0, 0.0, 0.0]})
	var aimed: Dictionary = g.evaluate(pose)
	var dir: Vector3 = (aimed["rotations"] as Array[Quaternion])[3] * Vector3(0.0, 0.0, -1.0)
	t.near(dir.distance_to(Vector3.RIGHT), 0.0, 0.001, "aim turns forward toward target")
	g.clear()
	g.add({"type": "aim", "bone": 3, "forward": [0.0, 0.0, -1.0], "target": [5.0, 0.0, 0.0], "max_angle": 0.2})
	var q_lim: Quaternion = (g.evaluate(pose)["rotations"] as Array[Quaternion])[3]
	t.near(q_lim.get_angle(), 0.2, 0.001, "aim honours max angle")
	# order: copy then limit vs limit then copy
	var rots: Array[Quaternion] = [Quaternion(Vector3.UP, 1.0), Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY]
	var pose2: Dictionary = ConstraintGraph.make_pose(pose["positions"], rots)
	var g1 := ConstraintGraph.new()
	g1.add({"type": "copy_rotation", "src": 0, "dst": 1})
	g1.add({"type": "limit_rotation", "bone": 1, "min_deg": [-180.0, -10.0, -180.0], "max_deg": [180.0, 10.0, 180.0]})
	var r1: Quaternion = (g1.evaluate(pose2)["rotations"] as Array[Quaternion])[1]
	t.near(rad_to_deg(r1.get_euler().y), 10.0, 0.01, "copy then limit clamps the copied rotation")
	var g2 := ConstraintGraph.new()
	g2.add({"type": "limit_rotation", "bone": 1, "min_deg": [-180.0, -10.0, -180.0], "max_deg": [180.0, 10.0, 180.0]})
	g2.add({"type": "copy_rotation", "src": 0, "dst": 1})
	var r2: Quaternion = (g2.evaluate(pose2)["rotations"] as Array[Quaternion])[1]
	t.near(rad_to_deg(r2.get_euler().y), rad_to_deg(1.0), 0.01, "limit then copy leaves the copied rotation")
	g2.move(1, 0)
	var r3: Quaternion = (g2.evaluate(pose2)["rotations"] as Array[Quaternion])[1]
	t.near(rad_to_deg(r3.get_euler().y), 10.0, 0.01, "move() reorders evaluation")
	t.eq((g2.last_log[0] as Dictionary)["type"], "copy_rotation", "log follows evaluation order")
	# fabrik + weight + disabled + invalid + json
	var chain_pose: Dictionary = ConstraintGraph.make_pose(PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0)]))
	var g3 := ConstraintGraph.new()
	g3.add({"type": "fabrik_chain", "bones": [0, 1, 2, 3], "target": [1.0, 2.0, 0.0], "iterations": 32})
	var fp: PackedVector3Array = g3.evaluate(chain_pose)["positions"]
	t.near(fp[3].distance_to(Vector3(1.0, 2.0, 0.0)), 0.0, 0.01, "fabrik reaches target")
	t.near(fp[0].length(), 0.0, 0.0001, "fabrik root fixed")
	g3.constraints[0]["weight"] = 0.5
	var half: PackedVector3Array = g3.evaluate(chain_pose)["positions"]
	t.near(half[3].distance_to(fp[3].lerp(Vector3(3.0, 0.0, 0.0), 0.5)), 0.0, 0.001, "weight blends toward the solved pose")
	g3.constraints[0]["enabled"] = false
	var off: PackedVector3Array = g3.evaluate(chain_pose)["positions"]
	t.near(off[3].x, 3.0, 0.0001, "disabled constraint skipped")
	t.eq(bool((g3.last_log[0] as Dictionary)["applied"]), false, "log reports skipped")
	g3.add({"type": "aim", "bone": 99, "target": [0.0, 0.0, 0.0]})
	g3.evaluate(chain_pose)
	t.eq(bool((g3.last_log[1] as Dictionary)["applied"]), false, "invalid bone id ignored")
	var g4 := ConstraintGraph.new()
	t.check(g4.from_json(g1.to_json()), "graph JSON loads")
	t.eq(g4.constraints.size(), 2, "constraints round trip")
	var r4: Quaternion = (g4.evaluate(pose2)["rotations"] as Array[Quaternion])[1]
	t.near(rad_to_deg(r4.get_euler().y), 10.0, 0.01, "JSON-loaded graph evaluates identically")
	g4.add({"type": "two_bone", "root": 0, "mid": 1, "tip": 2, "target": {"bone": 3}, "pole": [0.0, 1.0, 0.0]})
	t.check(g4.evaluate(pose2)["positions"] != null, "bone-relative target accepted")
