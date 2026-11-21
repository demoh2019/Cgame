extends RefCounted
## Motion Matching pose search: index vs brute force, bias, tags, pruning.

const MotionMatching = preload("res://scripts/client/motion_matching.gd")
const Builder = preload("res://scripts/client/motion_db_builder.gd")


func _frame(clips: Array, clip_name: String, k: int) -> Dictionary:
	for c in clips:
		var clip: Dictionary = c
		if clip["name"] == clip_name:
			var frames: Array = clip["frames"]
			return frames[k]
	return {}


func _query(db: MotionMatching, vel: Vector2, fr: Dictionary) -> Dictionary:
	var lf: Vector3 = fr["left_foot"]
	var rf: Vector3 = fr["right_foot"]
	var lv: Vector3 = fr["left_foot_vel"]
	var rv: Vector3 = fr["right_foot_vel"]
	return db.query_from(vel, 0.0, vel, 0.0, lf, rf, lv, rv)


func run(t) -> void:
	var clips: Array = Builder.synthesize_locomotion_clips()
	var db: MotionMatching = Builder.build_default_database()

	t.current = "database stats and normalisation"
	var st: Dictionary = db.stats()
	var frames_total: int = st["frames"]
	t.check(frames_total > 200, "database has frames")
	t.eq(st["dimensions"], MotionMatching.DIMS, "dimension count")
	var finite: bool = true
	for v in db.features:
		if not is_finite(v):
			finite = false
	for d in MotionMatching.DIMS:
		if not is_finite(db.mean[d]) or not is_finite(db.stdev[d]) or db.stdev[d] <= 0.0:
			finite = false
	t.check(finite, "normalisation finite")

	t.current = "indexed equals brute force"
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var worst: float = 0.0
	var mismatches: int = 0
	for i in 60:
		var idx := rng.randi_range(0, 30)
		var cl: Dictionary = clips[rng.randi_range(0, clips.size() - 1)]
		var frs: Array = cl["frames"]
		var base: Dictionary = frs[idx % frs.size()]
		var f: PackedFloat32Array = MotionMatching.frame_features(base)
		for d in MotionMatching.DIMS:
			f[d] += rng.randfn(0.0, 0.5)
		var q := {"features": f}
		var a: Dictionary = db.search(q)
		var b: Dictionary = db.brute_force_search(q)
		var ca: float = a["cost"]
		var cb: float = b["cost"]
		if ca > cb * 1.01 + 0.00001:
			mismatches += 1
		worst = maxf(worst, ca - cb)
	t.eq(mismatches, 0, "indexed search within 1% of brute force")

	t.current = "locomotion selection"
	var run_fr: Dictionary = _frame(clips, "run_forward", 5)
	var r: Dictionary = db.search(_query(db, Vector2(0.0, 4.0), run_fr))
	t.eq(r["clip"], "run_forward", "running query picks run clip")
	var idle_fr: Dictionary = _frame(clips, "idle", 3)
	r = db.search(_query(db, Vector2.ZERO, idle_fr))
	t.eq(r["clip"], "idle", "idle query picks idle")
	var strafe_fr: Dictionary = _frame(clips, "strafe_right", 4)
	r = db.search(_query(db, Vector2(1.4, 0.0), strafe_fr))
	t.eq(r["clip"], "strafe_right", "strafe query picks strafe")

	t.current = "continuing pose bias"
	var fa: PackedFloat32Array = MotionMatching.frame_features(_frame(clips, "walk_forward", 11))
	var fb: PackedFloat32Array = MotionMatching.frame_features(_frame(clips, "walk_forward", 12))
	var mid := PackedFloat32Array()
	mid.resize(MotionMatching.DIMS)
	for d in MotionMatching.DIMS:
		mid[d] = (fa[d] + fb[d]) * 0.5
	var qm := {"features": mid}
	var free: Dictionary = db.search(qm)
	var held: Dictionary = db.search(qm, "walk_forward", 11)
	t.eq(held["clip"], "walk_forward", "continuing keeps clip")
	t.eq(held["frame"], 12, "continuing frame+1 chosen")
	var fc: float = free["cost"]
	var hc: float = held["cost"]
	t.check(hc < fc or free["frame"] == 12, "bias lowers cost of continuing pose")
	var far: Dictionary = db.search(_query(db, Vector2(0.0, 4.0), run_fr), "idle", 3)
	t.eq(far["clip"], "run_forward", "bias does not trap a clearly better match")

	t.current = "tag filtering"
	r = db.search(_query(db, Vector2(0.0, 4.0), run_fr), "", -1, PackedStringArray(["strafe"]))
	var rc: String = r["clip"]
	t.check(rc.begins_with("strafe"), "required tag restricts clips")
	r = db.search(_query(db, Vector2(0.0, 4.0), run_fr), "", -1, PackedStringArray(["nonexistent"]))
	t.eq(r["frame"], -1, "no clip satisfies unknown tag")

	t.current = "spring trajectory"
	var goal := Vector2(0.0, 4.0)
	var vfar: Vector2 = MotionMatching.predict_velocity(Vector2.ZERO, goal, 0.27, 3.0)
	t.near(vfar.y, 4.0, 0.01, "spring converges to desired velocity")
	var vmid: Vector2 = MotionMatching.predict_velocity(Vector2.ZERO, goal, 0.27, 0.27)
	t.check(vmid.y > 1.0 and vmid.y < 3.5, "spring approaches monotonically near halflife")
	var spring_q: Dictionary = db.query_from(Vector2.ZERO, 0.0, goal, 0.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var tr: Array = spring_q["trajectory"]
	var tp0: Dictionary = tr[0]
	var tp2: Dictionary = tr[2]
	var p0: Vector2 = tp0["pos"]
	var p2: Vector2 = tp2["pos"]
	t.check(p2.y > p0.y and p2.y < 4.0 * 0.6, "trajectory accelerates but lags desired velocity")
	var turn_f: float = MotionMatching.predict_facing(0.0, 1.0, 0.27, 3.0)
	t.near(turn_f, 1.0, 0.01, "facing spring converges")

	t.current = "pruning"
	var before: int = db.frame_count()
	var tmp: MotionMatching = Builder.build_default_database()
	var removed: int = Builder.prune_redundant(tmp, 0.05)
	t.check(removed > 0, "prune removes near-duplicate frames")
	t.eq(tmp.frame_count(), before - removed, "frame count shrinks by removed")
	var pr: Dictionary = tmp.search(_query(tmp, Vector2(0.0, 4.0), run_fr))
	t.eq(pr["clip"], "run_forward", "search quality kept after pruning (run)")
	var pc: float = pr["cost"]
	t.check(pc < 0.5, "pruned run match stays close")
	pr = tmp.search(_query(tmp, Vector2.ZERO, idle_fr))
	t.eq(pr["clip"], "idle", "search quality kept after pruning (idle)")
	var pb: Dictionary = tmp.brute_force_search(_query(tmp, Vector2(1.4, 0.0), strafe_fr))
	var pi: Dictionary = tmp.search(_query(tmp, Vector2(1.4, 0.0), strafe_fr))
	var pbc: float = pb["cost"]
	var pic: float = pi["cost"]
	t.check(pic <= pbc * 1.01 + 0.00001, "index rebuilt correctly after pruning")

	t.current = "determinism"
	var db2: MotionMatching = Builder.build_default_database()
	t.eq(db2.features, db.features, "features identical across builds")
	var qd: Dictionary = _query(db, Vector2(0.7, 2.0), run_fr)
	var x1: Dictionary = db.search(qd)
	var x2: Dictionary = db2.search(qd)
	t.eq(x1["clip"], x2["clip"], "same clip")
	t.eq(x1["frame"], x2["frame"], "same frame")
	t.eq(x1["cost"], x2["cost"], "same cost")
