extends RefCounted
## Deterministic scenario record/replay (camera path + input script) and
## per-subsystem comparison of two perf captures.
## Original code (MIT-compatible).
##
## Recording: start_recording(), then record_frame(frame, camera_transform, inputs)
## each frame. Replay: load_scenario(dict), then step(frame, camera) which applies
## the recorded (or interpolated) camera transform and returns that frame's inputs.

var _frames: PackedInt32Array = PackedInt32Array()
var _xforms: Array = []  # Array of PackedFloat32Array(12): basis rows x,y,z + origin
var _inputs: Array = []  # Array of Array[Dictionary]
var recording: bool = false
var seed_value: int = 0


func start_recording(rng_seed: int = 0) -> void:
	_frames.clear()
	_xforms.clear()
	_inputs.clear()
	recording = true
	seed_value = rng_seed


func stop_recording() -> void:
	recording = false


## inputs: [{"action": "move_forward", "pressed": true, "strength": 1.0}, ...]
func record_frame(frame: int, xform: Transform3D, inputs: Array = []) -> void:
	if not recording:
		return
	_frames.append(frame)
	_xforms.append(_pack(xform))
	_inputs.append(inputs.duplicate(true))


func frame_count() -> int:
	return _frames.size()


func last_frame() -> int:
	return _frames[_frames.size() - 1] if not _frames.is_empty() else -1


func to_dict() -> Dictionary:
	var xs: Array = []
	for x in _xforms:
		var px: PackedFloat32Array = x
		xs.append(Array(px))
	return {"seed": seed_value, "frames": Array(_frames), "camera": xs, "inputs": _inputs.duplicate(true)}


func load_scenario(d: Dictionary) -> bool:
	_frames.clear()
	_xforms.clear()
	_inputs.clear()
	recording = false
	if not (d.has("frames") and d.has("camera")):
		return false
	var fr: Array = d["frames"]
	var cam: Array = d["camera"]
	var inp: Array = d.get("inputs", [])
	if fr.size() != cam.size():
		return false
	seed_value = int(d.get("seed", 0))
	for i in fr.size():
		_frames.append(int(fr[i]))
		var arr: Array = cam[i]
		var p := PackedFloat32Array()
		for v in arr:
			p.append(float(v))
		if p.size() != 12:
			return false
		_xforms.append(p)
		var in_i: Array = inp[i] if i < inp.size() else []
		_inputs.append(in_i)
	return true


## Camera transform for `frame` (exact when recorded, interpolated in between,
## clamped outside the recorded range). Same input always gives the same output.
func transform_at(frame: int) -> Transform3D:
	if _frames.is_empty():
		return Transform3D.IDENTITY
	var idx: int = _frames.bsearch(frame)
	if idx < _frames.size() and _frames[idx] == frame:
		return _unpack(_xforms[idx])
	if idx <= 0:
		return _unpack(_xforms[0])
	if idx >= _frames.size():
		return _unpack(_xforms[_frames.size() - 1])
	var f0: int = _frames[idx - 1]
	var f1: int = _frames[idx]
	var w: float = float(frame - f0) / float(f1 - f0)
	var a: Transform3D = _unpack(_xforms[idx - 1])
	var b: Transform3D = _unpack(_xforms[idx])
	return Transform3D(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), w), a.origin.lerp(b.origin, w))


func inputs_at(frame: int) -> Array:
	var idx: int = _frames.bsearch(frame)
	if idx < _frames.size() and _frames[idx] == frame:
		var res: Array = _inputs[idx]
		return res
	return []


## Apply the scenario to `camera` for `frame`; returns that frame's recorded inputs.
func step(frame: int, camera: Camera3D) -> Array:
	if camera != null:
		camera.transform = transform_at(frame)
	return inputs_at(frame)


static func _pack(t: Transform3D) -> PackedFloat32Array:
	var b: Basis = t.basis
	return PackedFloat32Array([
		b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	])


static func _unpack(p: PackedFloat32Array) -> Transform3D:
	return Transform3D(
		Basis(Vector3(p[0], p[1], p[2]), Vector3(p[3], p[4], p[5]), Vector3(p[6], p[7], p[8])),
		Vector3(p[9], p[10], p[11]))


# --- subsystem comparison -------------------------------------------------

## Mean and p95 per-frame ms for each subsystem (scope-name prefix before the
## first "/"; scopes without one go to "other"). Also "frame" for total frame ms.
static func subsystem_stats(cap: Dictionary) -> Dictionary:
	var per_sys: Dictionary = {}  # name -> PackedFloat32Array (per-frame ms)
	var frames: Array = cap.get("frames", [])
	var n: int = frames.size()
	for fi in n:
		var fd: Dictionary = frames[fi]
		var sums: Dictionary = {}
		var scopes: Dictionary = fd.get("scopes", {})
		for sname in scopes:
			var key: String = str(sname)
			var slash: int = key.find("/")
			var sys: String = key.substr(0, slash) if slash > 0 else "other"
			sums[sys] = float(sums.get(sys, 0.0)) + float(scopes[sname]) / 1000.0
		sums["frame"] = float(fd.get("ms", 0.0))
		for sys in sums:
			if not per_sys.has(sys):
				per_sys[sys] = PackedFloat32Array()
			var arr: PackedFloat32Array = per_sys[sys]
			arr.append(float(sums[sys]))
			per_sys[sys] = arr
	var out: Dictionary = {}
	for sys in per_sys:
		var arr: PackedFloat32Array = per_sys[sys]
		var total: float = 0.0
		for v in arr:
			total += v
		var sorted: PackedFloat32Array = arr.duplicate()
		sorted.sort()
		var p95_i: int = clampi(int(ceil(0.95 * float(sorted.size()))) - 1, 0, sorted.size() - 1)
		out[sys] = {"mean_ms": total / float(arr.size()), "p95_ms": sorted[p95_i], "frames": arr.size()}
	return out


## Flags subsystems whose mean (or p95) grew by more than the threshold.
## thresholds: {"default_pct": 10, "min_abs_ms": 0.05, "<subsystem>": pct}
## Returns {"subsystems": {name: {...}}, "regressions": [names], "improvements": [names]}.
static func compare_captures(base: Dictionary, cur: Dictionary, thresholds: Dictionary = {}) -> Dictionary:
	var default_pct: float = float(thresholds.get("default_pct", 10.0))
	var min_abs: float = float(thresholds.get("min_abs_ms", 0.05))
	var bs: Dictionary = subsystem_stats(base)
	var cs: Dictionary = subsystem_stats(cur)
	var names: Dictionary = {}
	for k in bs:
		names[k] = true
	for k in cs:
		names[k] = true
	var subs: Dictionary = {}
	var regressions: Array[String] = []
	var improvements: Array[String] = []
	for k in names:
		var name: String = str(k)
		var b: Dictionary = bs.get(name, {})
		var c: Dictionary = cs.get(name, {})
		var bm: float = float(b.get("mean_ms", 0.0))
		var cm: float = float(c.get("mean_ms", 0.0))
		var bp: float = float(b.get("p95_ms", 0.0))
		var cp: float = float(c.get("p95_ms", 0.0))
		var limit: float = float(thresholds.get(name, default_pct))
		var pct: float = 0.0
		if bm > 0.000001:
			pct = (cm - bm) / bm * 100.0
		elif cm > 0.0:
			pct = 100.0
		var p95_pct: float = 0.0
		if bp > 0.000001:
			p95_pct = (cp - bp) / bp * 100.0
		var mean_reg: bool = pct > limit and (cm - bm) >= min_abs
		var p95_reg: bool = p95_pct > limit and (cp - bp) >= min_abs
		var reg: bool = mean_reg or p95_reg
		subs[name] = {
			"base_mean_ms": bm, "cur_mean_ms": cm, "mean_pct": pct,
			"base_p95_ms": bp, "cur_p95_ms": cp, "p95_pct": p95_pct,
			"limit_pct": limit, "regressed": reg,
			"new": b.is_empty(), "removed": c.is_empty(),
		}
		if reg:
			regressions.append(name)
		elif pct < -limit and (bm - cm) >= min_abs:
			improvements.append(name)
	regressions.sort()
	improvements.sort()
	return {"subsystems": subs, "regressions": regressions, "improvements": improvements}
