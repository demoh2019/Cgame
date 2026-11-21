extends RefCounted
## Motion-capture cleanup toolkit: noise filtering, rotation smoothing, gap filling,
## spike removal, foot-skate cleanup, root-motion extraction, key reduction, retiming.
## All functions are static and operate on whole tracks sampled at a constant fps.
##
## Sources / credits (algorithms re-implemented from the published descriptions, no GPL code):
##  - One Euro filter: Gery Casiez, Nicolas Roussel, Daniel Vogel, "1 Euro Filter" (CHI 2012).
##    Reference implementation (1euro.js / OneEuroFilter.cpp) is BSD-3-Clause,
##    Copyright (c) Gery Casiez. This port follows its structure (adaptive-cutoff
##    exponential smoothing with a low-passed derivative).
##  - Butterworth low-pass: RBJ "Audio EQ Cookbook" biquad coefficients (Robert
##    Bristow-Johnson, public-domain-style cookbook formulas), Q = 1/sqrt(2); applied
##    forward then backward (filtfilt-style, odd-reflection padding) for zero phase.
##  - Ramer-Douglas-Peucker simplification (public-domain algorithm), applied in time.
##  - Cubic Hermite / slerp gap filling and rotation-vector (log-map) filtering are
##    textbook techniques.
## No Apache-2.0 code is included.

const TAU_F: float = TAU


# ---------------------------------------------------------------- One Euro filter

static func _oe_alpha(te: float, cutoff: float) -> float:
	var tau: float = 1.0 / (TAU_F * maxf(cutoff, 0.000001))
	return 1.0 / (1.0 + tau / te)


## Adaptive low-pass: low cutoff when slow (kills jitter), high cutoff when fast (low lag).
static func one_euro_positions(track: PackedVector3Array, fps: float, min_cutoff: float = 1.0,
		beta: float = 0.0, d_cutoff: float = 1.0) -> PackedVector3Array:
	var n: int = track.size()
	var out := PackedVector3Array()
	out.resize(n)
	if n == 0:
		return out
	var te: float = 1.0 / maxf(fps, 0.001)
	var x_prev: Vector3 = track[0]
	var dx_prev: Vector3 = Vector3.ZERO
	out[0] = x_prev
	var a_d: float = _oe_alpha(te, d_cutoff)
	for i in range(1, n):
		var x: Vector3 = track[i]
		var dx: Vector3 = (x - x_prev) / te
		var edx: Vector3 = dx_prev + (dx - dx_prev) * a_d
		var cutoff: float = min_cutoff + beta * edx.length()
		var a: float = _oe_alpha(te, cutoff)
		var xh: Vector3 = x_prev + (x - x_prev) * a
		out[i] = xh
		x_prev = xh
		dx_prev = edx
	return out


# ---------------------------------------------------------------- Butterworth

static func _biquad(x: PackedFloat64Array, fps: float, cutoff: float) -> PackedFloat64Array:
	var n: int = x.size()
	var out := PackedFloat64Array()
	out.resize(n)
	if n == 0:
		return out
	var fc: float = clampf(cutoff, 0.001, fps * 0.45)
	var w0: float = TAU_F * fc / fps
	var cs: float = cos(w0)
	var al: float = sin(w0) / (2.0 * 0.7071067811865476)
	var a0: float = 1.0 + al
	var b0: float = (1.0 - cs) * 0.5 / a0
	var b1: float = (1.0 - cs) / a0
	var b2: float = b0
	var a1: float = -2.0 * cs / a0
	var a2: float = (1.0 - al) / a0
	var x1: float = x[0]
	var x2: float = x[0]
	var y1: float = x[0]
	var y2: float = x[0]
	for i in n:
		var xi: float = x[i]
		var yi: float = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		out[i] = yi
		x2 = x1
		x1 = xi
		y2 = y1
		y1 = yi
	return out


static func _reverse64(a: PackedFloat64Array) -> PackedFloat64Array:
	var n: int = a.size()
	var r := PackedFloat64Array()
	r.resize(n)
	for i in n:
		r[i] = a[n - 1 - i]
	return r


static func _filtfilt(x: PackedFloat64Array, fps: float, cutoff: float) -> PackedFloat64Array:
	var n: int = x.size()
	if n < 3:
		return x.duplicate()
	var pad: int = mini(n - 1, int(3.0 * fps / maxf(cutoff, 0.001)) + 3)
	var p := PackedFloat64Array()
	p.resize(n + 2 * pad)
	for i in range(1, pad + 1):
		p[pad - i] = 2.0 * x[0] - x[i]
		p[pad + n - 1 + i] = 2.0 * x[n - 1] - x[n - 1 - i]
	for i in n:
		p[pad + i] = x[i]
	var f: PackedFloat64Array = _biquad(p, fps, cutoff)
	f = _reverse64(f)
	f = _biquad(f, fps, cutoff)
	f = _reverse64(f)
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		out[i] = f[pad + i]
	return out


## Zero-phase (forward + backward) 2nd-order Butterworth low-pass on a Vector3 track.
## The effective order is 4 and the -3 dB point drops to about 0.64 * cutoff_hz.
static func butterworth(track: PackedVector3Array, fps: float, cutoff_hz: float) -> PackedVector3Array:
	var n: int = track.size()
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	var zs := PackedFloat64Array()
	xs.resize(n)
	ys.resize(n)
	zs.resize(n)
	for i in n:
		var v: Vector3 = track[i]
		xs[i] = v.x
		ys[i] = v.y
		zs[i] = v.z
	xs = _filtfilt(xs, fps, cutoff_hz)
	ys = _filtfilt(ys, fps, cutoff_hz)
	zs = _filtfilt(zs, fps, cutoff_hz)
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		out[i] = Vector3(xs[i], ys[i], zs[i])
	return out


# ---------------------------------------------------------------- rotations

## Make a quaternion track hemisphere-consistent (q and -q are the same rotation).
static func make_continuous(rots: Array[Quaternion]) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for i in rots.size():
		var q: Quaternion = rots[i].normalized()
		if i > 0 and out[i - 1].dot(q) < 0.0:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)
		out.append(q)
	return out


static func _quat_log(q: Quaternion) -> Vector3:
	var qq: Quaternion = q
	if qq.w < 0.0:
		qq = Quaternion(-qq.x, -qq.y, -qq.z, -qq.w)
	var v := Vector3(qq.x, qq.y, qq.z)
	var s: float = v.length()
	if s < 0.00000001:
		return v * 2.0
	var angle: float = 2.0 * atan2(s, qq.w)
	return v / s * angle


static func _quat_exp(v: Vector3) -> Quaternion:
	var angle: float = v.length()
	if angle < 0.000000001:
		return Quaternion(v.x * 0.5, v.y * 0.5, v.z * 0.5, 1.0).normalized()
	return Quaternion(v / angle, angle)


## Low-pass a rotation track in the tangent space (rotation vectors) of the first sample,
## so the result stays unit-length and sign flips (q vs -q) in the input are harmless.
static func smooth_rotations(rots: Array[Quaternion], fps: float, cutoff: float) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	if rots.is_empty():
		return out
	var cont: Array[Quaternion] = make_continuous(rots)
	var ref: Quaternion = cont[0]
	var ref_inv: Quaternion = ref.inverse()
	var logs := PackedVector3Array()
	logs.resize(cont.size())
	for i in cont.size():
		logs[i] = _quat_log(ref_inv * cont[i])
	var sm: PackedVector3Array = butterworth(logs, fps, cutoff)
	for i in sm.size():
		out.append((ref * _quat_exp(sm[i])).normalized())
	return out


# ---------------------------------------------------------------- spikes and gaps

static func _median(vals: PackedFloat64Array) -> float:
	var n: int = vals.size()
	if n == 0:
		return 0.0
	var s: PackedFloat64Array = vals.duplicate()
	s.sort()
	if n % 2 == 1:
		return s[n / 2]
	return 0.5 * (s[n / 2 - 1] + s[n / 2])


## Marks samples whose deviation from a 5-tap median exceeds threshold_sigma robust
## sigmas (MAD based) and re-interpolates them.
static func remove_spikes(track: PackedVector3Array, threshold_sigma: float = 4.0) -> PackedVector3Array:
	var n: int = track.size()
	if n < 5:
		return track.duplicate()
	var res := PackedFloat64Array()
	res.resize(n)
	for i in n:
		var lo: int = maxi(0, i - 2)
		var hi: int = mini(n - 1, i + 2)
		var mx := PackedFloat64Array()
		var my := PackedFloat64Array()
		var mz := PackedFloat64Array()
		for j in range(lo, hi + 1):
			var v: Vector3 = track[j]
			mx.append(v.x)
			my.append(v.y)
			mz.append(v.z)
		var med := Vector3(_median(mx), _median(my), _median(mz))
		res[i] = (track[i] - med).length()
	var med_r: float = _median(res)
	var dev := PackedFloat64Array()
	dev.resize(n)
	for i in n:
		dev[i] = absf(res[i] - med_r)
	var sigma: float = 1.4826 * _median(dev) + 0.000001
	var valid := PackedByteArray()
	valid.resize(n)
	for i in n:
		valid[i] = 0 if res[i] > med_r + threshold_sigma * sigma else 1
	return fill_gaps(track, valid)


static func _hermite(p0: Vector3, p1: Vector3, m0: Vector3, m1: Vector3, t: float, span: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return p0 * (2.0 * t3 - 3.0 * t2 + 1.0) + m0 * span * (t3 - 2.0 * t2 + t) \
		+ p1 * (-2.0 * t3 + 3.0 * t2) + m1 * span * (t3 - t2)


## Fills samples with valid[i] == 0 using cubic Hermite interpolation whose tangents come
## from the valid neighbours. Leading/trailing gaps hold the nearest valid sample.
static func fill_gaps(track: PackedVector3Array, valid: PackedByteArray) -> PackedVector3Array:
	var n: int = track.size()
	var out: PackedVector3Array = track.duplicate()
	if valid.size() != n or n == 0:
		return out
	var i: int = 0
	while i < n:
		if valid[i] != 0:
			i += 1
			continue
		var s: int = i
		while i < n and valid[i] == 0:
			i += 1
		var a: int = s - 1
		var b: int = i
		if a < 0 and b >= n:
			return out
		if a < 0:
			for k in range(s, b):
				out[k] = track[b]
		elif b >= n:
			for k in range(s, n):
				out[k] = track[a]
		else:
			var span: float = float(b - a)
			var chord: Vector3 = (track[b] - track[a]) / span
			var m0: Vector3 = chord
			if a - 1 >= 0 and valid[a - 1] != 0:
				m0 = track[a] - track[a - 1]
			var m1: Vector3 = chord
			if b + 1 < n and valid[b + 1] != 0:
				m1 = track[b + 1] - track[b]
			for k in range(s, b):
				out[k] = _hermite(track[a], track[b], m0, m1, float(k - a) / span, span)
	return out


## Rotation version of fill_gaps: slerp between the bracketing valid rotations.
static func fill_gaps_rotations(rots: Array[Quaternion], valid: PackedByteArray) -> Array[Quaternion]:
	var n: int = rots.size()
	var out: Array[Quaternion] = rots.duplicate()
	if valid.size() != n or n == 0:
		return out
	var i: int = 0
	while i < n:
		if valid[i] != 0:
			i += 1
			continue
		var s: int = i
		while i < n and valid[i] == 0:
			i += 1
		var a: int = s - 1
		var b: int = i
		if a < 0 and b >= n:
			return out
		for k in range(s, b):
			if a < 0:
				out[k] = rots[b]
			elif b >= n:
				out[k] = rots[a]
			else:
				var qb: Quaternion = rots[b]
				if rots[a].dot(qb) < 0.0:
					qb = Quaternion(-qb.x, -qb.y, -qb.z, -qb.w)
				out[k] = rots[a].slerp(qb, float(k - a) / float(b - a)).normalized()
	return out


# ---------------------------------------------------------------- feet

## Contact = foot near the lowest height of the track AND moving slowly (units/second).
## Runs shorter than three frames are dropped as noise.
static func detect_contacts(foot_track: PackedVector3Array, fps: float, height_threshold: float,
		speed_threshold: float) -> PackedByteArray:
	var n: int = foot_track.size()
	var out := PackedByteArray()
	out.resize(n)
	if n == 0:
		return out
	var ground: float = foot_track[0].y
	for i in n:
		ground = minf(ground, foot_track[i].y)
	for i in n:
		var lo: int = maxi(0, i - 1)
		var hi: int = mini(n - 1, i + 1)
		var speed: float = (foot_track[hi] - foot_track[lo]).length() * fps / float(maxi(1, hi - lo))
		var low: bool = foot_track[i].y - ground <= height_threshold
		out[i] = 1 if (low and speed <= speed_threshold) else 0
	var i2: int = 0
	while i2 < n:
		if out[i2] == 0:
			i2 += 1
			continue
		var s: int = i2
		while i2 < n and out[i2] != 0:
			i2 += 1
		if i2 - s < 3:
			for k in range(s, i2):
				out[k] = 0
	return out


static func _smoothstep01(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## Locks every planted run to a single position (the run mean) and blends the correction
## in before touchdown and out after lift-off so the foot does not pop.
static func fix_foot_skate(foot_track: PackedVector3Array, contacts: PackedByteArray,
		blend_frames: int = 4) -> PackedVector3Array:
	var n: int = foot_track.size()
	var out: PackedVector3Array = foot_track.duplicate()
	if contacts.size() != n or n == 0:
		return out
	var starts: Array[int] = []
	var ends: Array[int] = []
	var i: int = 0
	while i < n:
		if contacts[i] == 0:
			i += 1
			continue
		var s: int = i
		while i < n and contacts[i] != 0:
			i += 1
		starts.append(s)
		ends.append(i - 1)
	for r in starts.size():
		var s: int = starts[r]
		var e: int = ends[r]
		var plant: Vector3 = Vector3.ZERO
		for k in range(s, e + 1):
			plant += foot_track[k]
		plant /= float(e - s + 1)
		var off_in: Vector3 = plant - foot_track[s]
		var off_out: Vector3 = plant - foot_track[e]
		var gap_before: int = s if r == 0 else s - ends[r - 1] - 1
		var gap_after: int = (n - 1 - e) if r == starts.size() - 1 else starts[r + 1] - e - 1
		var lb: int = mini(blend_frames, int(floorf(float(gap_before) * 0.5)) if r > 0 else gap_before)
		var la: int = mini(blend_frames, int(floorf(float(gap_after) * 0.5)) if r < starts.size() - 1 else gap_after)
		for k in range(s, e + 1):
			out[k] = plant
		for d in range(1, lb + 1):
			var w: float = _smoothstep01(1.0 - float(d) / float(lb + 1))
			out[s - d] += off_in * w
		for d in range(1, la + 1):
			var w: float = _smoothstep01(1.0 - float(d) / float(la + 1))
			out[e + d] += off_out * w
	return out


# ---------------------------------------------------------------- root motion

## Splits hips motion into a ground-projected root (position + yaw from travel direction)
## and hips relative to that root. yaw is the rotation about +Y taking +Z onto the travel
## direction (forward = (sin yaw, 0, cos yaw)); it is unwrapped and held while stationary.
static func extract_root_motion(hips_track: PackedVector3Array) -> Dictionary:
	var n: int = hips_track.size()
	var root := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var local := PackedVector3Array()
	root.resize(n)
	yaw.resize(n)
	local.resize(n)
	var dirs := PackedFloat64Array()
	dirs.resize(n)
	var known := PackedByteArray()
	known.resize(n)
	for i in n:
		root[i] = Vector3(hips_track[i].x, 0.0, hips_track[i].z)
	for i in n:
		var lo: int = maxi(0, i - 1)
		var hi: int = mini(n - 1, i + 1)
		var d: Vector3 = root[hi] - root[lo]
		if d.length() > 0.000001:
			dirs[i] = atan2(d.x, d.z)
			known[i] = 1
	# Hold the last known heading; back-fill the leading unknown samples.
	var first: int = -1
	for i in n:
		if known[i] != 0:
			first = i
			break
	if first >= 0:
		var prev: float = dirs[first]
		for i in n:
			if known[i] != 0:
				var cur: float = dirs[i]
				cur = prev + wrapf(cur - prev, -PI, PI)
				dirs[i] = cur
				prev = cur
			else:
				dirs[i] = prev if i > first else dirs[first]
	for i in n:
		yaw[i] = dirs[i]
		var basis_inv: Basis = Basis(Vector3.UP, yaw[i]).inverse()
		local[i] = basis_inv * (hips_track[i] - root[i])
	return {"root_positions": root, "root_yaw": yaw, "hips_local": local}


# ---------------------------------------------------------------- key reduction / retime

## Ramer-Douglas-Peucker in time: keeps the fewest frame indices such that linear
## interpolation between kept keys stays within tolerance of every dropped sample.
static func reduce_keys(track: PackedVector3Array, tolerance: float) -> PackedInt32Array:
	var n: int = track.size()
	var out := PackedInt32Array()
	if n == 0:
		return out
	if n <= 2:
		for i in n:
			out.append(i)
		return out
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var worst: float = -1.0
		var worst_i: int = -1
		for i in range(seg.x + 1, seg.y):
			var t: float = float(i - seg.x) / float(seg.y - seg.x)
			var err: float = (track[i] - track[seg.x].lerp(track[seg.y], t)).length()
			if err > worst:
				worst = err
				worst_i = i
		if worst > tolerance and worst_i >= 0:
			keep[worst_i] = 1
			stack.append(Vector2i(seg.x, worst_i))
			stack.append(Vector2i(worst_i, seg.y))
	for i in n:
		if keep[i] != 0:
			out.append(i)
	return out


## Resamples a track from src_fps to dst_fps using Catmull-Rom interpolation.
static func retime(track: PackedVector3Array, src_fps: float, dst_fps: float) -> PackedVector3Array:
	var n: int = track.size()
	var out := PackedVector3Array()
	if n == 0 or src_fps <= 0.0 or dst_fps <= 0.0:
		return out
	var count: int = maxi(1, int(roundf(float(n - 1) * dst_fps / src_fps)) + 1)
	out.resize(count)
	for k in count:
		var src_t: float = float(k) * src_fps / dst_fps
		var i1: int = clampi(int(floorf(src_t)), 0, n - 1)
		var f: float = src_t - float(i1)
		var i0: int = maxi(i1 - 1, 0)
		var i2: int = mini(i1 + 1, n - 1)
		var i3: int = mini(i1 + 2, n - 1)
		out[k] = track[i1].cubic_interpolate(track[i2], track[i0], track[i3], f)
	return out


## Rotation retime (slerp between neighbouring source frames).
static func retime_rotations(rots: Array[Quaternion], src_fps: float, dst_fps: float) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	var n: int = rots.size()
	if n == 0 or src_fps <= 0.0 or dst_fps <= 0.0:
		return out
	var cont: Array[Quaternion] = make_continuous(rots)
	var count: int = maxi(1, int(roundf(float(n - 1) * dst_fps / src_fps)) + 1)
	for k in count:
		var src_t: float = float(k) * src_fps / dst_fps
		var i1: int = clampi(int(floorf(src_t)), 0, n - 1)
		var i2: int = mini(i1 + 1, n - 1)
		out.append(cont[i1].slerp(cont[i2], src_t - float(i1)).normalized())
	return out
