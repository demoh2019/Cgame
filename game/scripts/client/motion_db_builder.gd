extends RefCounted
## Builds / optimises Motion Matching databases without mocap.
## Synthetic analytic foot cycles are original work. Pruning follows the
## database-optimisation idea from Clavet (GDC 2016) and UE5 Pose Search.

const MotionMatching = preload("res://scripts/client/motion_matching.gd")

const FPS: float = 30.0


static func _foot_pos(t: float, vel: Vector2, period: float, side: float) -> Vector3:
	var lateral: float = 0.1 * side
	if period <= 0.0:
		return Vector3(lateral + 0.002 * sin(t * 2.0 + side), 0.0, 0.0)
	var phi: float = TAU * t / period + (PI if side > 0.0 else 0.0)
	var speed: float = vel.length()
	var dir: Vector2 = vel / speed if speed > 0.0001 else Vector2(0.0, 1.0)
	var amp: float = speed * period * 0.25
	var along: float = amp * sin(phi)
	var lift: float = 0.12 * maxf(0.0, cos(phi))
	return Vector3(lateral + dir.x * along, lift, dir.y * along)


static func _make_clip(clip_name: String, vel: Vector2, turn_rate: float, period: float,
		cycles: int, tags: PackedStringArray) -> Dictionary:
	var frame_n: int = int(round(maxf(period, 1.0) * FPS)) * cycles
	if period > 0.0:
		frame_n = int(round(period * FPS)) * cycles
	var frames: Array = []
	var eps: float = 0.01
	for k in frame_n:
		var t: float = float(k) / FPS
		var traj: Array = []
		for dt in MotionMatching.TRAJ_TIMES:
			traj.append({"pos": vel * dt, "facing": turn_rate * dt})
		var lf: Vector3 = _foot_pos(t, vel, period, -1.0)
		var rf: Vector3 = _foot_pos(t, vel, period, 1.0)
		var lv: Vector3 = (_foot_pos(t + eps, vel, period, -1.0) - _foot_pos(t - eps, vel, period, -1.0)) / (2.0 * eps)
		var rv: Vector3 = (_foot_pos(t + eps, vel, period, 1.0) - _foot_pos(t - eps, vel, period, 1.0)) / (2.0 * eps)
		frames.append({
			"root_velocity": vel,
			"root_facing": 0.0,
			"trajectory": traj,
			"left_foot": lf,
			"right_foot": rf,
			"left_foot_vel": lv,
			"right_foot_vel": rv,
		})
	return {"name": clip_name, "frames": frames, "fps": FPS, "loop": true, "tags": tags}


## Returns Array of {name, frames, fps, loop, tags}. Velocity is local (x right, y forward).
static func synthesize_locomotion_clips() -> Array:
	var clips: Array = []
	clips.append(_make_clip("idle", Vector2.ZERO, 0.0, 0.0, 1, PackedStringArray(["idle"])))
	clips[0]["frames"] = (clips[0]["frames"] as Array).slice(0, 1) if false else clips[0]["frames"]
	var loco := PackedStringArray(["locomotion", "walk"])
	clips.append(_make_clip("walk_forward", Vector2(0.0, 1.4), 0.0, 1.0, 2, loco))
	clips.append(_make_clip("walk_back", Vector2(0.0, -1.2), 0.0, 1.0, 2, loco))
	clips.append(_make_clip("run_forward", Vector2(0.0, 4.0), 0.0, 0.6, 3, PackedStringArray(["locomotion", "run"])))
	var strafe := PackedStringArray(["locomotion", "strafe"])
	clips.append(_make_clip("strafe_left", Vector2(-1.4, 0.0), 0.0, 1.0, 2, strafe))
	clips.append(_make_clip("strafe_right", Vector2(1.4, 0.0), 0.0, 1.0, 2, strafe))
	clips.append(_make_clip("turn_left", Vector2.ZERO, -2.2, 0.8, 2, PackedStringArray(["turn"])))
	clips.append(_make_clip("turn_right", Vector2.ZERO, 2.2, 0.8, 2, PackedStringArray(["turn"])))
	return clips


static func build_default_database() -> MotionMatching:
	var db := MotionMatching.new()
	for c in synthesize_locomotion_clips():
		var clip: Dictionary = c
		var frames: Array = clip["frames"]
		var fps: float = clip["fps"]
		var loop: bool = clip["loop"]
		var tags: PackedStringArray = clip["tags"]
		db.add_clip(String(clip["name"]), frames, fps, loop, tags)
	db.build()
	return db


## Removes frames within `threshold` (normalised, weighted distance) of an
## already kept frame of the same clip. Returns the removed count.
static func prune_redundant(db: MotionMatching, threshold: float) -> int:
	var n: int = db.clip_of.size()
	var keep := PackedByteArray()
	keep.resize(n)
	var thr_sq: float = threshold * threshold
	for ci in db.clip_names.size():
		var s: int = db.clip_start[ci]
		var kept: Array[int] = []
		for i in range(s, s + db.clip_count[ci]):
			var dup: bool = false
			for j in kept:
				if MotionMatching._dsq(db.features, i * MotionMatching.DIMS, db.features, j * MotionMatching.DIMS) < thr_sq:
					dup = true
					break
			if not dup:
				kept.append(i)
				keep[i] = 1
	return db.retain_frames(keep)
