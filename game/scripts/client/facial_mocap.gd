extends RefCounted
## Facial mocap pipeline: per-frame 2D landmarks (68-point dlib-style layout) ->
## FACS action unit activations -> blend shape weights, with neutral-frame
## calibration and One Euro smoothing.
##
## Landmark layout (0-based, dlib iBUG 300-W convention):
##   0-16 jaw, 17-21 person's right brow, 22-26 person's left brow, 27-30 nose
##   bridge, 31-35 nostrils, 36-41 person's right eye, 42-47 person's left eye,
##   48-59 outer lips, 60-67 inner lips. "Left"/"Right" outputs are the
##   person's sides (ARKit convention), i.e. left = image-right for a camera
##   that is not mirrored. Image coordinates are y-down.
##
## Credit / licensing: original implementation. Sources (concepts only, no code
## copied): FACS (Ekman & Friesen); eye aspect ratio blink metric, Soukupova &
## Cech, "Real-Time Eye Blink Detection using Facial Landmarks", CVWW 2016; One
## Euro filter, Casiez, Roussel & Vogel, CHI 2012 (algorithm is published; this
## is an independent implementation). The 68-point layout is from the iBUG 300-W
## annotation scheme.

const FacialRigData = preload("res://scripts/client/facial_rig_data.gd")

const LANDMARK_COUNT: int = 68

## Feature delta (inter-ocular distances) that maps to AU activation 1.
var ranges: Dictionary = {
	"AU1": 0.10, "AU2": 0.10, "AU4": 0.08, "AU5": 0.10,
	"AU12": 0.12, "AU15": 0.08, "AU20": 0.30,
	"AU25_gap": 0.08, "AU26_gap": 0.35, "AU26_chin": 0.30,
}
## One Euro filter parameters.
var min_cutoff: float = 1.5
var beta: float = 0.05
var d_cutoff: float = 1.0
var smoothing_enabled: bool = true

var rig: RefCounted = FacialRigData.default_rig()

## Neutral feature set; defaults describe a generic relaxed face until calibrated.
var neutral: Dictionary = {
	"brow_inner_l": 0.30, "brow_inner_r": 0.30, "brow_outer_l": 0.30, "brow_outer_r": 0.30,
	"ear_l": 0.40, "ear_r": 0.40,
	"lift_l": -0.07, "lift_r": -0.07,
	"mouth_width": 0.56, "lip_gap": 0.06, "chin_drop": 0.75,
}
var calibrated: bool = false

var _filters: Dictionary = {}


# ---- Feature extraction ----

## Normalises landmarks: origin at the mid-eye point, x along the inter-ocular
## axis (removes head roll), unit length = inter-ocular distance.
static func normalize_landmarks(lm: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if lm.size() < LANDMARK_COUNT:
		return out
	var a: Vector2 = lm[36]
	var b: Vector2 = lm[45]
	var axis: Vector2 = b - a
	var iod: float = maxf(axis.length(), 0.000001)
	var roll: float = axis.angle()
	var mid: Vector2 = (a + b) * 0.5
	out.resize(lm.size())
	for i in lm.size():
		out[i] = (lm[i] - mid).rotated(-roll) / iod
	return out


static func head_roll(lm: PackedVector2Array) -> float:
	if lm.size() < LANDMARK_COUNT:
		return 0.0
	return (lm[45] - lm[36]).angle()


static func _avg_y(n: PackedVector2Array, idx: Array[int]) -> float:
	var s: float = 0.0
	for i in idx:
		s += n[i].y
	return s / float(idx.size())


static func _ear(n: PackedVector2Array, o: int) -> float:
	# o = first index of an eye (36 or 42): corners o, o+3; lids o+1,o+2 over o+5,o+4.
	var w: float = maxf(n[o].distance_to(n[o + 3]), 0.000001)
	return (n[o + 1].distance_to(n[o + 5]) + n[o + 2].distance_to(n[o + 4])) / (2.0 * w)


## Raw normalised measurements for one frame (empty if the landmark set is invalid).
static func measure(lm: PackedVector2Array) -> Dictionary:
	if lm.size() < LANDMARK_COUNT:
		return {}
	var n: PackedVector2Array = normalize_landmarks(lm)
	var eye_r: float = _avg_y(n, [37, 38, 40, 41] as Array[int])
	var eye_l: float = _avg_y(n, [43, 44, 46, 47] as Array[int])
	var ref_y: float = (n[51].y + n[57].y) * 0.5
	return {
		"brow_inner_r": eye_r - n[21].y,
		"brow_inner_l": eye_l - n[22].y,
		"brow_outer_r": eye_r - (n[17].y + n[18].y) * 0.5,
		"brow_outer_l": eye_l - (n[25].y + n[26].y) * 0.5,
		"ear_r": _ear(n, 36),
		"ear_l": _ear(n, 42),
		"lift_r": ref_y - n[48].y,
		"lift_l": ref_y - n[54].y,
		"mouth_width": n[48].distance_to(n[54]),
		"lip_gap": n[62].distance_to(n[66]),
		"chin_drop": n[8].y - n[33].y,
	}


## Sets the neutral reference from one or more relaxed-face frames (averaged).
## Returns false if no valid frame was given.
func calibrate(frames: Array) -> bool:
	var acc := {}
	var count: int = 0
	for f in frames:
		var lm: PackedVector2Array = f
		var m: Dictionary = measure(lm)
		if m.is_empty():
			continue
		for k in m:
			acc[k] = float(acc.get(k, 0.0)) + float(m[k])
		count += 1
	if count == 0:
		return false
	for k in acc:
		neutral[k] = float(acc[k]) / float(count)
	calibrated = true
	reset_filters()
	return true


func calibrate_frame(lm: PackedVector2Array) -> bool:
	return calibrate([lm])


# ---- AU / blend shape solve ----

func _pos(delta: float, rng: float) -> float:
	return clampf(delta / rng, 0.0, 1.0)


## Unsmoothed AU activations (0..1) for one frame. Keys: AU1, AU2_L/R, AU4_L/R,
## AU5, AU12_L/R, AU15_L/R, AU20, AU25, AU26, AU45_L/R.
func solve_aus(lm: PackedVector2Array) -> Dictionary:
	var m: Dictionary = measure(lm)
	if m.is_empty():
		return {}
	var d := {}
	for k in m:
		d[k] = float(m[k]) - float(neutral[k])
	var aus := {}
	aus["AU1"] = _pos((float(d["brow_inner_l"]) + float(d["brow_inner_r"])) * 0.5, float(ranges["AU1"]))
	for s in ["l", "r"]:
		var up: String = s.to_upper()
		var inner: float = d["brow_inner_" + s]
		var outer: float = d["brow_outer_" + s]
		aus["AU2_" + up] = _pos(outer, float(ranges["AU2"]))
		aus["AU4_" + up] = _pos(-(inner + outer) * 0.5, float(ranges["AU4"]))
		var ear_n: float = maxf(float(neutral["ear_" + s]), 0.000001)
		aus["AU45_" + up] = clampf(-float(d["ear_" + s]) / (ear_n * 0.8), 0.0, 1.0)
		var lift: float = d["lift_" + s]
		aus["AU12_" + up] = _pos(lift, float(ranges["AU12"]))
		aus["AU15_" + up] = _pos(-lift, float(ranges["AU15"]))
	aus["AU5"] = _pos((float(d["ear_l"]) + float(d["ear_r"])) * 0.5, 0.4 * float(neutral["ear_l"]))
	var lift_avg: float = maxf(0.0, (float(d["lift_l"]) + float(d["lift_r"])) * 0.5)
	aus["AU20"] = _pos(float(d["mouth_width"]) - 0.5 * lift_avg, float(ranges["AU20"]))
	var gap: float = d["lip_gap"]
	var chin: float = d["chin_drop"]
	aus["AU25"] = _pos(gap, float(ranges["AU25_gap"]))
	aus["AU26"] = clampf((gap / float(ranges["AU26_gap"]) + chin / float(ranges["AU26_chin"])) * 0.5, 0.0, 1.0)
	return aus


## Full pipeline for one frame. `dt` is the time since the previous frame (s).
## Returns {"aus", "blendshapes", "head_roll"}; aus/blendshapes are smoothed.
func process(lm: PackedVector2Array, dt: float = 1.0 / 30.0) -> Dictionary:
	var raw: Dictionary = solve_aus(lm)
	if raw.is_empty():
		return {"aus": {}, "blendshapes": {}, "head_roll": 0.0}
	var aus := {}
	for k in raw:
		var v: float = raw[k]
		aus[k] = _smooth(str(k), v, dt) if smoothing_enabled else v
	var bs: Dictionary = rig.blend(aus)
	return {"aus": aus, "blendshapes": bs, "head_roll": head_roll(lm)}


# ---- One Euro filter ----

static func _alpha(cutoff: float, dt: float) -> float:
	var tau: float = 1.0 / (TAU * maxf(cutoff, 0.000001))
	return 1.0 / (1.0 + tau / maxf(dt, 0.000001))


func _smooth(key: String, x: float, dt: float) -> float:
	if not _filters.has(key):
		_filters[key] = {"x": x, "dx": 0.0}
		return x
	var st: Dictionary = _filters[key]
	var px: float = st["x"]
	var pdx: float = st["dx"]
	var dx: float = (x - px) / maxf(dt, 0.000001)
	var a_d: float = _alpha(d_cutoff, dt)
	var dx_hat: float = pdx + a_d * (dx - pdx)
	var cutoff: float = min_cutoff + beta * absf(dx_hat)
	var a: float = _alpha(cutoff, dt)
	var x_hat: float = px + a * (x - px)
	st["x"] = x_hat
	st["dx"] = dx_hat
	return x_hat


func reset_filters() -> void:
	_filters.clear()
