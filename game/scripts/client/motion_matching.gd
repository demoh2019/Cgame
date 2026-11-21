extends RefCounted
## Motion Matching pose-search database (data only, headless-testable).
##
## Concepts after Simon Clavet, "Motion Matching and The Road to Next-Gen
## Animation" (GDC 2016, For Honor), Daniel Holden's "Learned Motion Matching"
## (SIGGRAPH 2020) and his critically damped spring write-up (theorangeduck.com,
## "Spring-It-On"). Implementation is original; the spring closed form is the
## standard critically damped solution. Acceleration structure is a k-means
## bucket index with triangle-inequality pruning, so indexed search is exact.
##
## Feature layout (DIMS = 24):
##   0..1   root velocity (local space, x right / y forward)
##   2      root facing
##   3..11  3 trajectory samples at 0.2/0.4/0.6 s: pos.x, pos.y, facing (relative to root)
##   12..14 left foot pos, 15..17 right foot pos
##   18..20 left foot vel, 21..23 right foot vel

const DIMS: int = 24
const TRAJ_TIMES: Array[float] = [0.2, 0.4, 0.6]
const MIN_STD: float = 0.0001

## Per-feature-group weights (applied after mean/std normalisation).
var weights: Dictionary = {
	"velocity": 1.0,
	"facing": 0.5,
	"traj_pos": 1.0,
	"traj_facing": 0.5,
	"foot_pos": 0.6,
	"foot_vel": 0.4,
}
## Cost multiplier for the pose that continues the currently playing clip.
var continue_bias: float = 0.85
var spring_halflife: float = 0.27

# Built data (normalised, weight-scaled features, DIMS floats per frame).
var features := PackedFloat32Array()
var mean := PackedFloat32Array()
var stdev := PackedFloat32Array()
var dim_scale := PackedFloat32Array()
var clip_of := PackedInt32Array()
var frame_src := PackedInt32Array() ## original frame number inside the clip
var clip_names: Array[String] = []
var clip_start := PackedInt32Array()
var clip_count := PackedInt32Array()
var clip_tags: Array[PackedStringArray] = []

var _clips: Array[Dictionary] = []
var _clip_index: Dictionary = {}
var _centroids := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _members: Array[PackedInt32Array] = []
var _built: bool = false


func add_clip(clip_name: String, frames: Array, fps: float, loop: bool, tags := PackedStringArray()) -> void:
	_clips.append({"name": clip_name, "frames": frames, "fps": fps, "loop": loop, "tags": tags})
	_built = false


func frame_count() -> int:
	return clip_of.size()


func stats() -> Dictionary:
	return {
		"frames": clip_of.size(),
		"dimensions": DIMS,
		"clips": clip_names.size(),
		"buckets": _members.size(),
	}


static func frame_features(frame: Dictionary) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(DIMS)
	var rv: Vector2 = frame["root_velocity"]
	f[0] = rv.x
	f[1] = rv.y
	var rf: float = frame["root_facing"]
	f[2] = rf
	var traj: Array = frame["trajectory"]
	for i in 3:
		var tp: Dictionary = traj[i]
		var pos: Vector2 = tp["pos"]
		var fac: float = tp["facing"]
		f[3 + i * 3] = pos.x
		f[4 + i * 3] = pos.y
		f[5 + i * 3] = fac
	var lf: Vector3 = frame["left_foot"]
	var rfoot: Vector3 = frame["right_foot"]
	var lv: Vector3 = frame["left_foot_vel"]
	var rvv: Vector3 = frame["right_foot_vel"]
	_put3(f, 12, lf)
	_put3(f, 15, rfoot)
	_put3(f, 18, lv)
	_put3(f, 21, rvv)
	return f


static func _put3(f: PackedFloat32Array, at: int, v: Vector3) -> void:
	f[at] = v.x
	f[at + 1] = v.y
	f[at + 2] = v.z


func _dim_weights() -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(DIMS)
	var wv: float = weights["velocity"]
	var wf: float = weights["facing"]
	var wp: float = weights["traj_pos"]
	var wtf: float = weights["traj_facing"]
	var wfp: float = weights["foot_pos"]
	var wfv: float = weights["foot_vel"]
	w[0] = wv
	w[1] = wv
	w[2] = wf
	for i in 3:
		w[3 + i * 3] = wp
		w[4 + i * 3] = wp
		w[5 + i * 3] = wtf
	for d in range(12, 18):
		w[d] = wfp
	for d in range(18, 24):
		w[d] = wfv
	return w


func build() -> void:
	features = PackedFloat32Array()
	clip_of = PackedInt32Array()
	frame_src = PackedInt32Array()
	clip_names.clear()
	clip_start = PackedInt32Array()
	clip_count = PackedInt32Array()
	clip_tags.clear()
	_clip_index.clear()
	var raw := PackedFloat32Array()
	var total: int = 0
	for ci in _clips.size():
		var clip: Dictionary = _clips[ci]
		var frames: Array = clip["frames"]
		var cname: String = clip["name"]
		var ctags: PackedStringArray = clip["tags"]
		clip_names.append(cname)
		clip_tags.append(ctags)
		clip_start.append(total)
		clip_count.append(frames.size())
		_clip_index[cname] = ci
		for fi in frames.size():
			var fd: Dictionary = frames[fi]
			raw.append_array(frame_features(fd))
			clip_of.append(ci)
			frame_src.append(fi)
		total += frames.size()
	mean = PackedFloat32Array()
	mean.resize(DIMS)
	stdev = PackedFloat32Array()
	stdev.resize(DIMS)
	var w := _dim_weights()
	dim_scale = PackedFloat32Array()
	dim_scale.resize(DIMS)
	for d in DIMS:
		dim_scale[d] = sqrt(w[d])
	if total > 0:
		for d in DIMS:
			var s: float = 0.0
			for i in total:
				s += raw[i * DIMS + d]
			var m: float = s / float(total)
			var v: float = 0.0
			for i in total:
				var dv: float = raw[i * DIMS + d] - m
				v += dv * dv
			var sd: float = sqrt(v / float(total))
			if sd < MIN_STD:
				sd = 1.0
			mean[d] = m
			stdev[d] = sd
	features = PackedFloat32Array()
	features.resize(total * DIMS)
	for i in total:
		for d in DIMS:
			features[i * DIMS + d] = (raw[i * DIMS + d] - mean[d]) / stdev[d] * dim_scale[d]
	_build_index()
	_built = true


## Drops frames where keep[i] == 0 (keeps normalisation), then rebuilds the index.
func retain_frames(keep: PackedByteArray) -> int:
	var n: int = clip_of.size()
	var nf := PackedFloat32Array()
	var nc := PackedInt32Array()
	var ns := PackedInt32Array()
	var removed: int = 0
	var counts := PackedInt32Array()
	counts.resize(clip_names.size())
	for i in n:
		if keep[i] == 0:
			removed += 1
			continue
		nf.append_array(features.slice(i * DIMS, i * DIMS + DIMS))
		nc.append(clip_of[i])
		ns.append(frame_src[i])
		counts[clip_of[i]] += 1
	features = nf
	clip_of = nc
	frame_src = ns
	var run: int = 0
	for ci in clip_names.size():
		clip_start[ci] = run
		clip_count[ci] = counts[ci]
		run += counts[ci]
	_build_index()
	return removed


static func _dsq(a: PackedFloat32Array, ao: int, b: PackedFloat32Array, bo: int) -> float:
	var s: float = 0.0
	for d in DIMS:
		var x: float = a[ao + d] - b[bo + d]
		s += x * x
	return s


func _build_index() -> void:
	_centroids = PackedFloat32Array()
	_radius = PackedFloat32Array()
	_members = []
	var n: int = clip_of.size()
	if n == 0:
		return
	var k: int = clampi(int(sqrt(float(n)) * 0.5), 1, 64)
	# Deterministic farthest-point initialisation.
	var seeds := PackedInt32Array([0])
	var mind := PackedFloat32Array()
	mind.resize(n)
	for i in n:
		mind[i] = _dsq(features, i * DIMS, features, 0)
	while seeds.size() < k:
		var bi: int = 0
		var bd: float = -1.0
		for i in n:
			if mind[i] > bd:
				bd = mind[i]
				bi = i
		if bd <= 0.0:
			break
		seeds.append(bi)
		for i in n:
			var dd: float = _dsq(features, i * DIMS, features, bi * DIMS)
			if dd < mind[i]:
				mind[i] = dd
	k = seeds.size()
	_centroids.resize(k * DIMS)
	for c in k:
		for d in DIMS:
			_centroids[c * DIMS + d] = features[seeds[c] * DIMS + d]
	var assign := PackedInt32Array()
	assign.resize(n)
	for _it in 6:
		_assign_all(assign, k)
		var sums := PackedFloat32Array()
		sums.resize(k * DIMS)
		var cnt := PackedInt32Array()
		cnt.resize(k)
		for i in n:
			var c: int = assign[i]
			cnt[c] += 1
			for d in DIMS:
				sums[c * DIMS + d] += features[i * DIMS + d]
		for c in k:
			if cnt[c] > 0:
				for d in DIMS:
					_centroids[c * DIMS + d] = sums[c * DIMS + d] / float(cnt[c])
	_assign_all(assign, k)
	_radius.resize(k)
	for c in k:
		_members.append(PackedInt32Array())
	for i in n:
		var c2: int = assign[i]
		_members[c2].append(i)
		var r: float = sqrt(_dsq(features, i * DIMS, _centroids, c2 * DIMS))
		if r > _radius[c2]:
			_radius[c2] = r


func _assign_all(assign: PackedInt32Array, k: int) -> void:
	for i in assign.size():
		var best: int = 0
		var bd: float = INF
		for c in k:
			var dd: float = _dsq(features, i * DIMS, _centroids, c * DIMS)
			if dd < bd:
				bd = dd
				best = c
		assign[i] = best


func _normalize_query(query: Dictionary) -> PackedFloat32Array:
	var raw: PackedFloat32Array
	if query.has("features"):
		raw = query["features"]
	else:
		raw = frame_features(query)
	var q := PackedFloat32Array()
	q.resize(DIMS)
	for d in DIMS:
		q[d] = (raw[d] - mean[d]) / stdev[d] * dim_scale[d]
	return q


func _tag_mask(required: PackedStringArray) -> PackedByteArray:
	var ok := PackedByteArray()
	ok.resize(clip_names.size())
	for ci in clip_names.size():
		var good: bool = true
		for tg in required:
			if not clip_tags[ci].has(tg):
				good = false
				break
		ok[ci] = 1 if good else 0
	return ok


## Global index of the frame that follows (clip, frame), or -1.
func _next_index(clip_name: String, frame: int) -> int:
	if frame < 0 or not _clip_index.has(clip_name):
		return -1
	var ci: int = _clip_index[clip_name]
	var cnt: int = clip_count[ci]
	if cnt == 0:
		return -1
	var s: int = clip_start[ci]
	for i in range(s, s + cnt):
		if frame_src[i] > frame:
			return i
	var clip: Dictionary = _clips[ci]
	var looping: bool = clip["loop"]
	return s if looping else -1


func search(query: Dictionary, current_clip := "", current_frame := -1, required_tags := PackedStringArray()) -> Dictionary:
	return _search_impl(query, current_clip, current_frame, required_tags, true)


func brute_force_search(query: Dictionary, current_clip := "", current_frame := -1, required_tags := PackedStringArray()) -> Dictionary:
	return _search_impl(query, current_clip, current_frame, required_tags, false)


func _search_impl(query: Dictionary, current_clip: String, current_frame: int, required_tags: PackedStringArray, indexed: bool) -> Dictionary:
	var none := {"clip": "", "frame": -1, "cost": INF, "continuing": false}
	if not _built or clip_of.size() == 0:
		return none
	var q := _normalize_query(query)
	var ok := _tag_mask(required_tags)
	var best_sq: float = INF
	var best_i: int = -1
	if indexed:
		var nb: int = _members.size()
		var cd := PackedFloat32Array()
		cd.resize(nb)
		var order: Array[int] = []
		for b in nb:
			cd[b] = sqrt(_dsq(q, 0, _centroids, b * DIMS))
			order.append(b)
		order.sort_custom(func(a: int, b: int) -> bool: return cd[a] < cd[b])
		for b in order:
			var lower: float = cd[b] - _radius[b]
			if lower > 0.0 and lower * lower >= best_sq:
				continue
			for i in _members[b]:
				if ok[clip_of[i]] == 0:
					continue
				var s: float = _partial_dsq(q, i, best_sq)
				if s < best_sq:
					best_sq = s
					best_i = i
	else:
		for i in clip_of.size():
			if ok[clip_of[i]] == 0:
				continue
			var s2: float = _partial_dsq(q, i, best_sq)
			if s2 < best_sq:
				best_sq = s2
				best_i = i
	var cost: float = sqrt(best_sq) if best_i >= 0 else INF
	var continuing: bool = false
	var ci_next: int = _next_index(current_clip, current_frame)
	if ci_next >= 0 and ok[clip_of[ci_next]] == 1:
		var cc: float = sqrt(_dsq(q, 0, features, ci_next * DIMS)) * continue_bias
		if best_i < 0 or cc < cost:
			cost = cc
			best_i = ci_next
			continuing = true
	if best_i < 0:
		return none
	return {
		"clip": clip_names[clip_of[best_i]],
		"frame": frame_src[best_i],
		"cost": cost,
		"continuing": continuing,
	}


func _partial_dsq(q: PackedFloat32Array, i: int, limit: float) -> float:
	var s: float = 0.0
	var base: int = i * DIMS
	for d in DIMS:
		var x: float = q[d] - features[base + d]
		s += x * x
		if s >= limit:
			return s
	return s


# ---- Spring-damper trajectory prediction (Holden) ----

static func _spring_y(halflife: float) -> float:
	return 2.0 * 0.69314718 / maxf(halflife, 0.0001)


## Critically damped spring on a 2D value (zero initial rate of change).
static func predict_velocity(v0: Vector2, goal: Vector2, halflife: float, t: float) -> Vector2:
	var y: float = _spring_y(halflife)
	var j0: Vector2 = v0 - goal
	var e: float = exp(-y * t)
	return goal + e * (j0 + (j0 * y) * t)


static func predict_facing(facing: float, goal: float, halflife: float, t: float) -> float:
	var y: float = _spring_y(halflife)
	var j0: float = wrapf(facing - goal, -PI, PI)
	var e: float = exp(-y * t)
	return goal + e * (j0 + j0 * y * t)


func query_from(velocity: Vector2, facing: float, desired_velocity: Vector2, desired_facing: float,
		left_foot: Vector3, right_foot: Vector3, left_vel: Vector3, right_vel: Vector3) -> Dictionary:
	var traj: Array = []
	var pos := Vector2.ZERO
	var t: float = 0.0
	var step: float = 0.02
	var goal_facing: float = facing + wrapf(desired_facing - facing, -PI, PI)
	for target in TRAJ_TIMES:
		while t < target - 0.0001:
			var v: Vector2 = predict_velocity(velocity, desired_velocity, spring_halflife, t + step * 0.5)
			pos += v * step
			t += step
		var pf: float = predict_facing(facing, goal_facing, spring_halflife, target)
		traj.append({"pos": pos, "facing": pf - facing})
	var frame := {
		"root_velocity": velocity,
		"root_facing": facing,
		"trajectory": traj,
		"left_foot": left_foot,
		"right_foot": right_foot,
		"left_foot_vel": left_vel,
		"right_foot_vel": right_vel,
	}
	frame["features"] = frame_features(frame)
	return frame
