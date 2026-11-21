extends RefCounted
## Mocap cleanup: filters, spikes, gaps, rotations, foot skate, root motion, key reduction.

const Mocap = preload("res://scripts/client/mocap_cleanup.gd")

const FPS: float = 60.0


static func _rmse(a: PackedVector3Array, b: PackedVector3Array, from: int, to: int) -> float:
	var s: float = 0.0
	for i in range(from, to):
		s += (a[i] - b[i]).length_squared()
	return sqrt(s / float(to - from))


static func _quat_angle(a: Quaternion, b: Quaternion) -> float:
	return 2.0 * acos(minf(1.0, absf(a.dot(b))))


func run(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var n: int = 240
	var truth := PackedVector3Array()
	var noisy := PackedVector3Array()
	for i in n:
		var s: float = float(i) / FPS
		var p := Vector3(sin(TAU * 0.5 * s), 0.5 * cos(TAU * 0.7 * s), 0.2 * s)
		truth.append(p)
		noisy.append(p + Vector3(rng.randfn(0.0, 0.06), rng.randfn(0.0, 0.06), rng.randfn(0.0, 0.06)))

	t.current = "noise filters"
	var raw_err: float = _rmse(noisy, truth, 10, n - 10)
	var oe: PackedVector3Array = Mocap.one_euro_positions(noisy, FPS, 3.0, 0.5, 1.0)
	t.check(_rmse(oe, truth, 10, n - 10) < raw_err, "one euro is closer to truth than the raw noisy track")
	var bw: PackedVector3Array = Mocap.butterworth(noisy, FPS, 4.0)
	t.check(_rmse(bw, truth, 10, n - 10) < raw_err * 0.7, "butterworth is closer to truth than the raw noisy track")
	t.eq(oe.size(), n, "one euro keeps length")
	t.eq(bw.size(), n, "butterworth keeps length")

	# One Euro: adaptive cutoff gives lower lag on a fast ramp than a fixed low cutoff.
	var ramp := PackedVector3Array()
	for i in 120:
		var x: float = 0.0 if i < 60 else float(i - 60) * 0.1
		ramp.append(Vector3(x, 0.0, 0.0))
	var fixed_lp: PackedVector3Array = Mocap.one_euro_positions(ramp, FPS, 1.0, 0.0, 1.0)
	var adaptive: PackedVector3Array = Mocap.one_euro_positions(ramp, FPS, 1.0, 5.0, 1.0)
	var lag_fixed: float = ramp[119].x - fixed_lp[119].x
	var lag_adapt: float = ramp[119].x - adaptive[119].x
	t.check(lag_adapt < lag_fixed * 0.5, "one euro beta cuts lag on fast motion (%.3f vs %.3f)" % [lag_adapt, lag_fixed])

	# Zero phase: a clean in-band sine must come out with no time shift.
	var clean := PackedVector3Array()
	for i in n:
		clean.append(Vector3(sin(TAU * 1.0 * float(i) / FPS), 0.0, 0.0))
	var zp: PackedVector3Array = Mocap.butterworth(clean, FPS, 8.0)
	var best_shift: int = 0
	var best_err: float = INF
	for shift in range(-4, 5):
		var e: float = 0.0
		for i in range(20, n - 20):
			e += absf(zp[i].x - clean[i + shift].x)
		if e < best_err:
			best_err = e
			best_shift = shift
	t.eq(best_shift, 0, "butterworth zero-phase: best alignment at zero shift")
	t.check(_rmse(zp, clean, 20, n - 20) < 0.02, "butterworth passes in-band sine almost unchanged")
	var causal: PackedVector3Array = Mocap.one_euro_positions(clean, FPS, 2.0, 0.0, 1.0)
	t.check(absf(causal[100].x - clean[100].x) > absf(zp[100].x - clean[100].x), "causal filter lags where zero-phase does not")

	t.current = "spikes"
	var spiked: PackedVector3Array = truth.duplicate()
	spiked[100] += Vector3(5.0, -3.0, 4.0)
	spiked[101] += Vector3(-2.0, 2.0, 0.0)
	var despiked: PackedVector3Array = Mocap.remove_spikes(spiked, 4.0)
	t.check((despiked[100] - truth[100]).length() < 0.1, "spike removed at 100")
	t.check((despiked[101] - truth[101]).length() < 0.1, "spike removed at 101")
	t.check((despiked[50] - truth[50]).length() < 0.05, "clean samples essentially untouched")

	t.current = "gap fill"
	var valid := PackedByteArray()
	valid.resize(n)
	valid.fill(1)
	var broken: PackedVector3Array = truth.duplicate()
	for i in range(80, 90):
		valid[i] = 0
		broken[i] = Vector3.ZERO
	var filled: PackedVector3Array = Mocap.fill_gaps(broken, valid)
	var worst: float = 0.0
	for i in range(80, 90):
		worst = maxf(worst, (filled[i] - truth[i]).length())
	t.check(worst < 0.03, "gap filled close to truth (worst %.4f)" % worst)
	var max_step: float = 0.0
	for i in range(78, 92):
		max_step = maxf(max_step, (filled[i + 1] - filled[i]).length())
	t.check(max_step < 0.1, "gap fill is continuous at the boundaries")
	valid[0] = 0
	valid[n - 1] = 0
	var edge: PackedVector3Array = Mocap.fill_gaps(broken, valid)
	t.eq(edge[0], broken[1], "leading gap holds nearest valid")
	t.eq(edge[n - 1], broken[n - 2], "trailing gap holds nearest valid")

	t.current = "rotations"
	var rots: Array[Quaternion] = []
	var true_rots: Array[Quaternion] = []
	for i in 120:
		var ang: float = 0.8 * sin(TAU * 0.5 * float(i) / FPS)
		var q := Quaternion(Vector3(0.3, 1.0, 0.2).normalized(), ang)
		true_rots.append(q)
		var jitter := Quaternion(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized(), rng.randfn(0.0, 0.03))
		var nq: Quaternion = (q * jitter).normalized()
		if i % 3 == 1:
			nq = Quaternion(-nq.x, -nq.y, -nq.z, -nq.w)
		rots.append(nq)
	var sm: Array[Quaternion] = Mocap.smooth_rotations(rots, FPS, 4.0)
	t.eq(sm.size(), rots.size(), "smoothed rotation count")
	var units_ok: bool = true
	var cont_ok: bool = true
	var err_in: float = 0.0
	var err_out: float = 0.0
	for i in sm.size():
		if absf(sm[i].length() - 1.0) > 0.0001:
			units_ok = false
		if i > 0 and sm[i - 1].dot(sm[i]) < 0.9:
			cont_ok = false
		if i >= 10 and i < sm.size() - 10:
			err_in += _quat_angle(rots[i], true_rots[i])
			err_out += _quat_angle(sm[i], true_rots[i])
	t.check(units_ok, "smoothed quaternions stay unit length")
	t.check(cont_ok, "sign flips in the input do not break continuity")
	t.check(err_out < err_in * 0.6, "smoothed rotations closer to truth than the noisy input")
	var rv := PackedByteArray()
	rv.resize(10)
	rv.fill(1)
	var rt: Array[Quaternion] = []
	for i in 10:
		rt.append(Quaternion(Vector3.UP, float(i) * 0.1))
	rv[4] = 0
	rv[5] = 0
	var rf: Array[Quaternion] = Mocap.fill_gaps_rotations(rt, rv)
	t.check(_quat_angle(rf[4], rt[4]) < 0.001 and _quat_angle(rf[5], rt[5]) < 0.001, "rotation gaps slerp to the right place")

	t.current = "foot contacts and skate"
	var foot := PackedVector3Array()
	for cycle in 2:
		var base_x: float = float(cycle)
		for f in 60:
			if f < 30:
				foot.append(Vector3(base_x + 0.003 * float(f), 0.0, 0.0))
			else:
				var u: float = float(f - 30) / 30.0
				foot.append(Vector3(base_x + 0.09 + u * 0.91, 0.12 * sin(PI * u), 0.0))
	var contacts: PackedByteArray = Mocap.detect_contacts(foot, FPS, 0.03, 0.4)
	t.eq(contacts.size(), foot.size(), "contacts sized to track")
	t.eq(int(contacts[15]), 1, "mid stance 1 is a contact")
	t.eq(int(contacts[75]), 1, "mid stance 2 is a contact")
	t.eq(int(contacts[45]), 0, "mid swing is not a contact")
	t.eq(int(contacts[105]), 0, "mid swing 2 is not a contact")
	var skate_before: float = 0.0
	var skate_after: float = 0.0
	var fixed: PackedVector3Array = Mocap.fix_foot_skate(foot, contacts)
	for i in range(1, foot.size()):
		if contacts[i] != 0 and contacts[i - 1] != 0:
			skate_before += (foot[i] - foot[i - 1]).length()
			skate_after += (fixed[i] - fixed[i - 1]).length()
	t.check(skate_before > 0.01, "synthetic walk really skates")
	t.check(skate_after < 0.0001, "foot skate ~0 during contacts (%.6f)" % skate_after)
	var max_jump: float = 0.0
	for i in range(1, fixed.size()):
		max_jump = maxf(max_jump, (fixed[i] - fixed[i - 1]).length())
	t.check(max_jump < 0.1, "blending leaves no pop (max step %.3f)" % max_jump)

	t.current = "root motion"
	var hips := PackedVector3Array()
	for i in 60:
		hips.append(Vector3(float(i) * 0.02, 1.0, 0.1))
	for i in range(1, 60):
		hips.append(Vector3(59.0 * 0.02, 1.0, 0.1 + float(i) * 0.02))
	var rm: Dictionary = Mocap.extract_root_motion(hips)
	var rp: PackedVector3Array = rm["root_positions"]
	var ry: PackedFloat32Array = rm["root_yaw"]
	var hl: PackedVector3Array = rm["hips_local"]
	t.eq(rp.size(), hips.size(), "root positions sized to hips")
	t.near(rp[30].y, 0.0, 0.0001, "root is ground-projected")
	t.near(rp[30].x, hips[30].x, 0.0001, "root keeps horizontal position")
	t.near(ry[30], PI * 0.5, 0.01, "walking +X faces yaw 90 degrees")
	t.near(ry[100], 0.0, 0.05, "walking +Z faces yaw 0")
	t.near(hl[30].y, 1.0, 0.0001, "hips local keeps height")
	t.near(hl[30].x, 0.0, 0.0001, "hips local has no horizontal offset along a straight line")
	t.near(hl[30].z, 0.0, 0.0001, "hips local sits on the root")
	var still: Dictionary = Mocap.extract_root_motion(PackedVector3Array([Vector3(0, 1, 0), Vector3(0, 1, 0)]))
	var still_yaw: PackedFloat32Array = still["root_yaw"]
	t.eq(still_yaw[1], 0.0, "stationary hips keep yaw 0")

	t.current = "key reduction and retime"
	var curve := PackedVector3Array()
	for i in 120:
		var s2: float = float(i) / FPS
		curve.append(Vector3(sin(TAU * 0.5 * s2), 0.3 * s2, 0.0))
	var tol: float = 0.01
	var keys: PackedInt32Array = Mocap.reduce_keys(curve, tol)
	t.check(keys.size() < 60, "far fewer keys (%d of 120)" % keys.size())
	t.eq(keys[0], 0, "first key kept")
	t.eq(keys[keys.size() - 1], 119, "last key kept")
	var key_err: float = 0.0
	for k in range(keys.size() - 1):
		var a: int = keys[k]
		var b: int = keys[k + 1]
		for i in range(a, b + 1):
			var u2: float = float(i - a) / float(b - a)
			key_err = maxf(key_err, (curve[i] - curve[a].lerp(curve[b], u2)).length())
	t.check(key_err <= tol + 0.00001, "reconstruction error under tolerance (%.5f)" % key_err)
	t.eq(Mocap.reduce_keys(PackedVector3Array(), 0.1).size(), 0, "empty track has no keys")
	var up: PackedVector3Array = Mocap.retime(curve, 30.0, 60.0)
	t.eq(up.size(), 119 * 2 + 1, "retime 30->60 length")
	t.check((up[2] - curve[1]).length() < 0.0001, "retime keeps source samples")
	var down: PackedVector3Array = Mocap.retime(curve, 60.0, 24.0)
	t.eq(down.size(), int(roundf(119.0 * 24.0 / 60.0)) + 1, "retime 60->24 length")
	t.check((down[down.size() - 1] - curve[119]).length() < 0.2, "retime ends near the last sample")
