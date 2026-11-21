extends RefCounted
## Foot locking, distance matching and orientation warping.

const FootLocking = preload("res://scripts/client/foot_locking.gd")
const DistanceMatching = preload("res://scripts/client/distance_matching.gd")


func run(t) -> void:
	var flat: Callable = func(_x: float, _z: float) -> float: return 0.0
	var both: Dictionary = {"left": 1.0, "right": 1.0}
	var none: Dictionary = {"left": 0.0, "right": 0.0}

	t.current = "foot locking"
	var fl := FootLocking.new()
	var feet: Dictionary = {"left": Vector3(0.2, 0.08, 0.0), "right": Vector3(-0.2, 0.1, 0.5)}
	var res: Dictionary = fl.update(0.1, feet, both, flat)
	var l: Dictionary = res["left"]
	var lt: Vector3 = l["target"]
	t.check(l["locked"], "planted foot locks")
	t.near(lt.y, 0.0, 0.0001, "lock snaps to ground")
	t.near(float(l["weight"]), 1.0, 0.0001, "full weight after blend in")

	var moved: Dictionary = {"left": Vector3(0.3, 0.08, 0.1), "right": Vector3(-0.2, 0.1, 0.5)}
	res = fl.update(0.016, moved, both, flat)
	l = res["left"]
	lt = l["target"]
	t.check(l["locked"], "stays locked under slight body motion")
	t.near(lt.x, 0.2, 0.0001, "locked position fixed x")
	t.near(lt.z, 0.0, 0.0001, "locked position fixed z")

	var far: Dictionary = {"left": Vector3(0.8, 0.0, 0.0), "right": Vector3(-0.2, 0.1, 0.5)}
	res = fl.update(0.016, far, both, flat)
	l = res["left"]
	t.check(not l["locked"], "releases beyond max stretch")
	var r: Dictionary = res["right"]
	t.check(r["locked"], "other foot independent when one releases")
	res = fl.update(0.016, far, both, flat)
	l = res["left"]
	t.check(not l["locked"], "released foot does not relock while still planted")

	var fl2 := FootLocking.new()
	fl2.update(0.1, feet, both, flat)
	res = fl2.update(0.1, feet, {"left": 0.0, "right": 1.0}, flat)
	l = res["left"]
	r = res["right"]
	t.check(not l["locked"], "lift-off unlocks")
	var w1: float = l["weight"]
	t.check(w1 > 0.0 and w1 < 1.0, "weight blends out, not instant")
	t.check(r["locked"], "right still planted")
	res = fl2.update(0.2, feet, {"left": 0.0, "right": 1.0}, flat)
	l = res["left"]
	t.near(float(l["weight"]), 0.0, 0.0001, "fully blended out after BLEND_OUT")
	var at: Vector3 = l["target"]
	t.near(at.y, 0.08, 0.0001, "target returns to animation")

	var fl3 := FootLocking.new()
	fl3.update(0.1, feet, none, flat)
	res = fl3.update(0.1, feet, none, flat)
	l = res["left"]
	t.check(not l["locked"], "swing foot is never locked")

	t.near(FootLocking.pelvis_offset(0.0, 0.0, 0.1, 0.05), -0.1, 0.0001, "pelvis drops by larger negative correction")
	t.near(FootLocking.pelvis_offset(0.0, 0.0, 1.0, 1.0), -0.25, 0.0001, "pelvis offset clamped at -0.25")
	t.near(FootLocking.pelvis_offset(0.2, 0.3, 0.0, 0.0), 0.0, 0.0001, "pelvis never raised")

	t.current = "distance matching"
	var dist := PackedFloat32Array([2.0, 1.0, 0.5, 0.0])
	var times := PackedFloat32Array([0.0, 0.2, 0.3, 0.5])
	t.near(DistanceMatching.playback_time_for_distance(dist, times, 1.5), 0.1, 0.0001, "interpolates decreasing curve")
	t.near(DistanceMatching.playback_time_for_distance(dist, times, 0.5), 0.3, 0.0001, "exact sample")
	t.near(DistanceMatching.playback_time_for_distance(dist, times, 9.0), 0.0, 0.0001, "clamps above range")
	t.near(DistanceMatching.playback_time_for_distance(dist, times, -1.0), 0.5, 0.0001, "clamps below range")
	var up := PackedFloat32Array([0.0, 1.0, 3.0])
	var up_t := PackedFloat32Array([0.0, 0.5, 1.5])
	t.near(DistanceMatching.playback_time_for_distance(up, up_t, 2.0), 1.0, 0.0001, "increasing curve works")
	t.near(DistanceMatching.playback_time_for_distance(PackedFloat32Array(), PackedFloat32Array(), 1.0), 0.0, 0.0001, "empty curve safe")

	t.near(DistanceMatching.stride_play_rate(4.0, 4.0), 1.0, 0.0001, "matching speed plays at 1")
	t.near(DistanceMatching.stride_play_rate(10.0, 4.0), 1.35, 0.0001, "rate clamped high")
	t.near(DistanceMatching.stride_play_rate(1.0, 4.0), 0.75, 0.0001, "rate clamped low")
	t.near(DistanceMatching.stride_play_rate(3.0, 0.0), 1.0, 0.0001, "bad authored speed safe")

	t.current = "orientation warp"
	var fwd: Dictionary = DistanceMatching.orientation_warp(Vector2(0, 1), 0.0)
	t.near(float(fwd["lower_body_yaw"]), 0.0, 0.0001, "forward needs no warp")
	var s30: Dictionary = DistanceMatching.orientation_warp(Vector2(sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0))), 0.0)
	t.near(float(s30["lower_body_yaw"]), deg_to_rad(30.0), 0.001, "small strafe follows velocity")
	t.near(float(s30["upper_body_yaw"]), -deg_to_rad(30.0), 0.001, "upper body counter-rotates")
	var side: Dictionary = DistanceMatching.orientation_warp(Vector2(1, 0), 0.0)
	t.near(float(side["lower_body_yaw"]), deg_to_rad(60.0), 0.001, "pure strafe clamped to max angle")
	var back: Dictionary = DistanceMatching.orientation_warp(Vector2(0, -1), 0.0)
	t.near(float(back["lower_body_yaw"]), 0.0, 0.001, "backwards folds to no warp")
	var back_off: Dictionary = DistanceMatching.orientation_warp(Vector2(sin(deg_to_rad(160.0)), cos(deg_to_rad(160.0))), 0.0)
	t.near(float(back_off["lower_body_yaw"]), deg_to_rad(-20.0), 0.001, "backwards offset warps small residual")
	var still: Dictionary = DistanceMatching.orientation_warp(Vector2.ZERO, 1.0)
	t.near(float(still["lower_body_yaw"]), 0.0, 0.0001, "no velocity no warp")
