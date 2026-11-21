extends RefCounted
## Motion Matching tooling: search profiler, feature-weight optimiser (minimises
## pose jitter on a validation query set) and an auto database builder that
## infers clip tags from the motion itself.
##
## Credit / licensing: original implementation. Ideas: Clavet, GDC 2016 "Motion
## Matching and The Road to Next-Gen Animation" (weights tuned for stable
## selection) and the database-tuning workflow described in the Unreal Engine
## Pose Search documentation (no source copied). Coordinate search over weight
## multipliers is textbook derivative-free optimisation. No third-party code.

const MotionMatching = preload("res://scripts/client/motion_matching.gd")
const MotionDBBuilder = preload("res://scripts/client/motion_db_builder.gd")

const WEIGHT_KEYS: Array[String] = ["velocity", "facing", "traj_pos", "traj_facing", "foot_pos", "foot_vel"]


# ---- Profiler ----

## Profiles the indexed search over `queries` (each a query Dictionary). Returns
## timing stats (microseconds), the share of k-means buckets skipped by the
## triangle-inequality bound, and the distribution of chosen costs.
static func profile(db: MotionMatching, queries: Array, required_tags: PackedStringArray = PackedStringArray()) -> Dictionary:
	var times: Array[float] = []
	var costs: Array[float] = []
	var pruned: int = 0
	var visited_total: int = 0
	var bucket_total: int = 0
	var frames_scored: int = 0
	var ok: PackedByteArray = db._tag_mask(required_tags)
	for qd in queries:
		var query: Dictionary = qd
		var t0: int = Time.get_ticks_usec()
		var res: Dictionary = db.search(query, "", -1, required_tags)
		times.append(float(Time.get_ticks_usec() - t0))
		costs.append(float(res["cost"]))
		var pr: Dictionary = _count_pruned(db, db._normalize_query(query), ok)
		pruned += int(pr["pruned"])
		visited_total += int(pr["visited"])
		frames_scored += int(pr["frames"])
		bucket_total += int(pr["pruned"]) + int(pr["visited"])
	var n: int = queries.size()
	var out := {
		"queries": n,
		"frames": db.frame_count(),
		"buckets": db.stats()["buckets"],
		"search_us_avg": _mean(times),
		"search_us_max": _max(times),
		"search_us_p95": _percentile(times, 0.95),
		"pruned_bucket_pct": 100.0 * float(pruned) / float(maxi(bucket_total, 1)),
		"frames_scored_avg": float(frames_scored) / float(maxi(n, 1)),
		"cost_min": _min(costs),
		"cost_mean": _mean(costs),
		"cost_max": _max(costs),
		"cost_p50": _percentile(costs, 0.5),
		"cost_p90": _percentile(costs, 0.9),
		"cost_histogram": _histogram(costs, 8),
	}
	return out


## Replays the bucket loop of MotionMatching._search_impl counting skipped buckets.
static func _count_pruned(db: MotionMatching, q: PackedFloat32Array, ok: PackedByteArray) -> Dictionary:
	var nb: int = db._members.size()
	var cd := PackedFloat32Array()
	cd.resize(nb)
	var order: Array[int] = []
	for b in nb:
		cd[b] = sqrt(MotionMatching._dsq(q, 0, db._centroids, b * MotionMatching.DIMS))
		order.append(b)
	order.sort_custom(func(a: int, c: int) -> bool: return cd[a] < cd[c])
	var best_sq: float = INF
	var pruned: int = 0
	var visited: int = 0
	var frames: int = 0
	for b in order:
		var lower: float = cd[b] - db._radius[b]
		if lower > 0.0 and lower * lower >= best_sq:
			pruned += 1
			continue
		visited += 1
		for i in db._members[b]:
			if ok[db.clip_of[i]] == 0:
				continue
			frames += 1
			var s: float = db._partial_dsq(q, i, best_sq)
			if s < best_sq:
				best_sq = s
	return {"pruned": pruned, "visited": visited, "frames": frames}


static func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for v in a:
		s += v
	return s / float(a.size())


static func _min(a: Array[float]) -> float:
	var m: float = INF
	for v in a:
		m = minf(m, v)
	return m if not a.is_empty() else 0.0


static func _max(a: Array[float]) -> float:
	var m: float = -INF
	for v in a:
		m = maxf(m, v)
	return m if not a.is_empty() else 0.0


static func _percentile(a: Array[float], p: float) -> float:
	if a.is_empty():
		return 0.0
	var s: Array[float] = a.duplicate()
	s.sort()
	var k: int = clampi(int(ceil(p * float(s.size()))) - 1, 0, s.size() - 1)
	return s[k]


static func _histogram(a: Array[float], bins: int) -> PackedInt32Array:
	var h := PackedInt32Array()
	h.resize(bins)
	if a.is_empty():
		return h
	var lo: float = _min(a)
	var hi: float = _max(a)
	var span: float = maxf(hi - lo, 0.000001)
	for v in a:
		var b: int = clampi(int((v - lo) / span * float(bins)), 0, bins - 1)
		h[b] += 1
	return h


# ---- Jitter metric + optimiser ----

## Pose jitter over an ordered validation query sequence: mean fixed-metric
## distance between consecutively chosen poses (raw features scaled by the
## database's own standard deviations, so the metric does not depend on the
## weights under test) plus a switch penalty for every non-contiguous jump.
static func jitter(db: MotionMatching, queries: Array, switch_penalty: float = 1.0) -> float:
	var prev_feat := PackedFloat32Array()
	var prev_clip: String = ""
	var prev_frame: int = -1
	var total: float = 0.0
	var steps: int = 0
	for qd in queries:
		var query: Dictionary = qd
		var res: Dictionary = db.search(query, prev_clip, prev_frame)
		var clip: String = res["clip"]
		var frame: int = res["frame"]
		if clip == "":
			continue
		var feat: PackedFloat32Array = _raw_pose_features(db, clip, frame)
		if not prev_feat.is_empty():
			var d: float = 0.0
			for k in MotionMatching.DIMS:
				var x: float = (feat[k] - prev_feat[k]) / db.stdev[k]
				d += x * x
			total += sqrt(d)
			var contiguous: bool = clip == prev_clip and frame >= prev_frame and frame - prev_frame <= 2
			if not contiguous:
				total += switch_penalty
			steps += 1
		prev_feat = feat
		prev_clip = clip
		prev_frame = frame
	return total / float(maxi(steps, 1))


static func _raw_pose_features(db: MotionMatching, clip: String, frame: int) -> PackedFloat32Array:
	var ci: int = db._clip_index[clip]
	var c: Dictionary = db._clips[ci]
	var frames: Array = c["frames"]
	var fd: Dictionary = frames[frame]
	return MotionMatching.frame_features(fd)


static func clone_with_weights(db: MotionMatching, weights: Dictionary) -> MotionMatching:
	var out := MotionMatching.new()
	out.weights = weights.duplicate()
	out.continue_bias = db.continue_bias
	out.spring_halflife = db.spring_halflife
	for c in db._clips:
		var clip: Dictionary = c
		var frames: Array = clip["frames"]
		var fps: float = clip["fps"]
		var loop: bool = clip["loop"]
		var tags: PackedStringArray = clip["tags"]
		out.add_clip(String(clip["name"]), frames, fps, loop, tags)
	out.build()
	return out


## Coordinate-descent search over per-group weight multipliers minimising jitter()
## on the validation sequence. Never worse than the starting weights. Returns
## {"weights", "before", "after", "evaluations", "history"}; `db` is untouched
## unless `apply` is true (then its weights are replaced and it is rebuilt).
static func optimize_weights(db: MotionMatching, validation: Array, passes: int = 2, apply: bool = false) -> Dictionary:
	var best_w: Dictionary = db.weights.duplicate()
	var best: float = jitter(db, validation)
	var before: float = best
	var evals: int = 1
	var history: Array[float] = [best]
	var factors: Array[float] = [0.25, 0.5, 2.0, 4.0]
	for _p in passes:
		var improved: bool = false
		for key in WEIGHT_KEYS:
			var base: float = best_w[key]
			var key_best: float = base
			for f in factors:
				var trial: Dictionary = best_w.duplicate()
				trial[key] = base * f
				var cand: MotionMatching = clone_with_weights(db, trial)
				var j: float = jitter(cand, validation)
				evals += 1
				if j < best - 0.000001:
					best = j
					key_best = base * f
					improved = true
			best_w[key] = key_best
			history.append(best)
		if not improved:
			break
	if apply:
		db.weights = best_w.duplicate()
		db.build()
	return {"weights": best_w, "before": before, "after": best, "evaluations": evals, "history": history}


# ---- Auto builder ----

## Infers descriptive tags from a clip's motion: idle / locomotion / walk / run /
## strafe / backward / turn / loop.
static func infer_tags(frames: Array) -> PackedStringArray:
	var tags := PackedStringArray()
	if frames.is_empty():
		return tags
	var sum_v := Vector2.ZERO
	var sum_speed: float = 0.0
	var sum_turn: float = 0.0
	for f in frames:
		var fd: Dictionary = f
		var v: Vector2 = fd["root_velocity"]
		sum_v += v
		sum_speed += v.length()
		var traj: Array = fd["trajectory"]
		var t_last: Dictionary = traj[traj.size() - 1]
		var tf: float = t_last["facing"]
		sum_turn += tf / MotionMatching.TRAJ_TIMES[MotionMatching.TRAJ_TIMES.size() - 1]
	var n: float = float(frames.size())
	var avg_v: Vector2 = sum_v / n
	var speed: float = sum_speed / n
	var turn: float = absf(sum_turn / n)
	if speed < 0.1:
		if turn > 0.5:
			tags.append("turn")
		else:
			tags.append("idle")
	else:
		tags.append("locomotion")
		tags.append("run" if speed > 2.5 else "walk")
		if absf(avg_v.x) > absf(avg_v.y):
			tags.append("strafe")
		elif avg_v.y < -0.1:
			tags.append("backward")
	var first: PackedFloat32Array = MotionMatching.frame_features(frames[0])
	var last: PackedFloat32Array = MotionMatching.frame_features(frames[frames.size() - 1])
	var d: float = 0.0
	for k in MotionMatching.DIMS:
		d += (first[k] - last[k]) * (first[k] - last[k])
	if frames.size() > 2 and sqrt(d) < 0.25 * maxf(1.0, speed):
		tags.append("loop")
	return tags


## Builds a database from clip dictionaries {name, frames, fps, loop, tags}.
## With `auto_tag`, inferred tags are merged with authored ones. A positive
## `prune_threshold` drops redundant frames. Returns {db, tags, pruned}.
static func auto_build(clips: Array, auto_tag: bool = true, prune_threshold: float = 0.0, weights: Dictionary = {}) -> Dictionary:
	var db := MotionMatching.new()
	if not weights.is_empty():
		for k in weights:
			db.weights[k] = weights[k]
	var tag_report := {}
	for c in clips:
		var clip: Dictionary = c
		var frames: Array = clip["frames"]
		var tags := PackedStringArray()
		if clip.has("tags"):
			tags = clip["tags"]
		if auto_tag:
			for tg in infer_tags(frames):
				if not tags.has(tg):
					tags.append(tg)
		var fps: float = float(clip.get("fps", 30.0))
		var loop: bool = bool(clip.get("loop", false))
		var cname: String = clip["name"]
		db.add_clip(cname, frames, fps, loop, tags)
		tag_report[cname] = tags
	db.build()
	var pruned: int = 0
	if prune_threshold > 0.0:
		pruned = MotionDBBuilder.prune_redundant(db, prune_threshold)
	return {"db": db, "tags": tag_report, "pruned": pruned}
