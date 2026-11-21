extends RefCounted
## Layered facial animation graph driving blend shapes (ARKit-style 52-shape names).
## Layers, evaluated in order and clamped to 0..1 at the end:
##   1. base emotion pose (FACS action units -> blend shapes)
##   2. additive pain / aggression layers
##   3. visemes from lip_sync.gd (A-H + X)
##   4. procedural blinks (deterministic random interval 2-6 s)
##   5. eye saccades (deterministic micro-targets)
##
## Concepts from the Facial Action Coding System (Ekman & Friesen; public research taxonomy),
## the Apple ARKit blend-shape naming convention, and Oculus/Rhubarb viseme shapes
## (Rhubarb Lip Sync, Daniel Wolf, MIT, https://github.com/DanielSWolf/rhubarb-lip-sync).
## Clean-room implementation; no third-party code copied.

const BLINK_DURATION := 0.2
const BLINK_MIN_INTERVAL := 2.0
const BLINK_MAX_INTERVAL := 6.0
const SACCADE_MIN_INTERVAL := 0.4
const SACCADE_MAX_INTERVAL := 2.0
const SACCADE_TRAVEL := 0.04
const SACCADE_AMPLITUDE := 0.35

## FACS action unit -> {blend shape: weight at AU intensity 1}.
const AU_SHAPES := {
	"AU1": {"browInnerUp": 1.0},
	"AU2": {"browOuterUpLeft": 1.0, "browOuterUpRight": 1.0},
	"AU4": {"browDownLeft": 1.0, "browDownRight": 1.0},
	"AU5": {"eyeWideLeft": 1.0, "eyeWideRight": 1.0},
	"AU6": {"cheekSquintLeft": 1.0, "cheekSquintRight": 1.0, "eyeSquintLeft": 0.4, "eyeSquintRight": 0.4},
	"AU7": {"eyeSquintLeft": 1.0, "eyeSquintRight": 1.0},
	"AU9": {"noseSneerLeft": 1.0, "noseSneerRight": 1.0},
	"AU10": {"mouthUpperUpLeft": 1.0, "mouthUpperUpRight": 1.0},
	"AU12": {"mouthSmileLeft": 1.0, "mouthSmileRight": 1.0},
	"AU15": {"mouthFrownLeft": 1.0, "mouthFrownRight": 1.0},
	"AU17": {"mouthShrugLower": 1.0},
	"AU20": {"mouthStretchLeft": 1.0, "mouthStretchRight": 1.0},
	"AU23": {"mouthPressLeft": 1.0, "mouthPressRight": 1.0},
	"AU25": {"mouthLowerDownLeft": 0.4, "mouthLowerDownRight": 0.4},
	"AU26": {"jawOpen": 1.0},
	"AU45": {"eyeBlinkLeft": 1.0, "eyeBlinkRight": 1.0},
}
## Emotion -> {AU: intensity}.
const EMOTIONS := {
	"neutral": {},
	"happy": {"AU6": 0.7, "AU12": 0.85},
	"sad": {"AU1": 0.8, "AU4": 0.4, "AU15": 0.7, "AU17": 0.3},
	"angry": {"AU4": 0.9, "AU5": 0.3, "AU7": 0.5, "AU9": 0.3, "AU10": 0.3, "AU23": 0.6},
	"fear": {"AU1": 0.8, "AU2": 0.6, "AU5": 0.8, "AU20": 0.6, "AU26": 0.3},
	"surprise": {"AU1": 0.8, "AU2": 0.8, "AU5": 0.9, "AU26": 0.6},
	"disgust": {"AU9": 0.8, "AU10": 0.6, "AU15": 0.3, "AU17": 0.3},
}
const PAIN_AUS := {"AU1": 0.5, "AU4": 0.6, "AU6": 0.4, "AU7": 0.8, "AU20": 0.6, "AU10": 0.3}
const AGGRESSION_AUS := {"AU4": 0.8, "AU7": 0.4, "AU9": 0.5, "AU10": 0.5, "AU23": 0.5}
## Viseme (A-H, X) -> blend shapes.
const VISEME_SHAPES := {
	"A": {"mouthPressLeft": 0.7, "mouthPressRight": 0.7, "mouthClose": 0.6},
	"B": {"jawOpen": 0.15, "mouthStretchLeft": 0.3, "mouthStretchRight": 0.3},
	"C": {"jawOpen": 0.45, "mouthLowerDownLeft": 0.3, "mouthLowerDownRight": 0.3},
	"D": {"jawOpen": 0.85, "mouthLowerDownLeft": 0.5, "mouthLowerDownRight": 0.5,
		"mouthUpperUpLeft": 0.2, "mouthUpperUpRight": 0.2},
	"E": {"jawOpen": 0.5, "mouthFunnel": 0.5},
	"F": {"jawOpen": 0.2, "mouthPucker": 0.8, "mouthFunnel": 0.5},
	"G": {"jawOpen": 0.1, "mouthRollLower": 0.6, "mouthUpperUpLeft": 0.4, "mouthUpperUpRight": 0.4},
	"H": {"jawOpen": 0.3, "mouthLowerDownLeft": 0.2, "mouthLowerDownRight": 0.2},
	"X": {},
}

var seed_value := 1
var additive_pain := 0.0
var additive_aggression := 0.0
var blink_enabled := true
var saccades_enabled := true
var _blink_starts: Array[float] = []
var _saccade_starts: Array[float] = []


func _init(p_seed := 1) -> void:
	seed_value = p_seed


## Deterministic pseudo-random value in [0, 1) for stream `salt`, index `k`.
func _rand(salt: int, k: int) -> float:
	var x: int = (k * 374761393 + seed_value * 668265263 + salt * 2246822519) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = (x ^ (x >> 16)) & 0x7fffffff
	return float(x & 0xffff) / 65536.0


func evaluate(t: float, emotion: String, emotion_weight: float, viseme_weights: Dictionary) -> Dictionary:
	var w := {}
	# 1. base emotion pose
	if EMOTIONS.has(emotion):
		_add_aus(w, EMOTIONS[emotion], emotion_weight)
	# 2. additive layers
	if additive_pain > 0.0:
		_add_aus(w, PAIN_AUS, additive_pain)
	if additive_aggression > 0.0:
		_add_aus(w, AGGRESSION_AUS, additive_aggression)
	# 3. visemes
	for key in viseme_weights:
		var vname := str(key)
		if VISEME_SHAPES.has(vname):
			_add_shapes(w, VISEME_SHAPES[vname], float(viseme_weights[key]))
	# 4. blinks (take the max so a blink always closes the lids)
	if blink_enabled:
		var b := blink_weight(t)
		if b > 0.0:
			for side in ["Left", "Right"]:
				var shape: String = "eyeBlink" + str(side)
				w[shape] = maxf(float(w.get(shape, 0.0)), b)
	# 5. saccades
	if saccades_enabled:
		_add_gaze(w, t)
	for key in w.keys():
		w[key] = clampf(float(w[key]), 0.0, 1.0)
	return w


func blink_weight(t: float) -> float:
	if t < 0.0:
		return 0.0
	while _blink_starts.is_empty() or _blink_starts[_blink_starts.size() - 1] <= t:
		var k := _blink_starts.size()
		var prev := _blink_starts[k - 1] if k > 0 else 0.0
		var gap := BLINK_MIN_INTERVAL + (BLINK_MAX_INTERVAL - BLINK_MIN_INTERVAL) * _rand(1, k)
		_blink_starts.append(prev + gap)
	var idx := _blink_starts.bsearch(t, false) - 1
	# bsearch(false) = first index with value > t; the candidate blink is the one before it.
	if idx < 0:
		return 0.0
	var p := (t - _blink_starts[idx]) / BLINK_DURATION
	if p < 0.0 or p > 1.0:
		return 0.0
	return p / 0.35 if p < 0.35 else 1.0 - (p - 0.35) / 0.65


## Eye look target (x, y) in -1..1 at time t.
func gaze_at(t: float) -> Vector2:
	if t < 0.0:
		return Vector2.ZERO
	while _saccade_starts.is_empty() or _saccade_starts[_saccade_starts.size() - 1] <= t:
		var k := _saccade_starts.size()
		var prev := _saccade_starts[k - 1] if k > 0 else 0.0
		_saccade_starts.append(prev + SACCADE_MIN_INTERVAL + (SACCADE_MAX_INTERVAL - SACCADE_MIN_INTERVAL) * _rand(2, k))
	var idx := _saccade_starts.bsearch(t, false) - 1
	if idx < 0:
		return _saccade_target(-1)
	var cur := _saccade_target(idx)
	var prev_target := _saccade_target(idx - 1)
	var s := clampf((t - _saccade_starts[idx]) / SACCADE_TRAVEL, 0.0, 1.0)
	return prev_target.lerp(cur, s)


func apply_to(mesh_instance: MeshInstance3D, weights: Dictionary) -> int:
	if mesh_instance == null or mesh_instance.mesh == null:
		return 0
	var applied := 0
	for key in weights:
		var idx := mesh_instance.find_blend_shape_by_name(StringName(str(key)))
		if idx >= 0:
			mesh_instance.set_blend_shape_value(idx, clampf(float(weights[key]), 0.0, 1.0))
			applied += 1
	return applied


func _saccade_target(k: int) -> Vector2:
	if k < 0:
		return Vector2.ZERO
	return Vector2(_rand(3, k) * 2.0 - 1.0, _rand(4, k) * 2.0 - 1.0)


func _add_gaze(w: Dictionary, t: float) -> void:
	var g := gaze_at(t) * SACCADE_AMPLITUDE
	var right := maxf(g.x, 0.0)
	var left := maxf(-g.x, 0.0)
	var up := maxf(g.y, 0.0)
	var down := maxf(-g.y, 0.0)
	_add(w, "eyeLookOutRight", right)
	_add(w, "eyeLookInLeft", right)
	_add(w, "eyeLookInRight", left)
	_add(w, "eyeLookOutLeft", left)
	for side in ["Left", "Right"]:
		_add(w, "eyeLookUp" + str(side), up)
		_add(w, "eyeLookDown" + str(side), down)


func _add_aus(w: Dictionary, aus: Dictionary, scale: float) -> void:
	for au in aus:
		var shapes: Dictionary = AU_SHAPES.get(au, {})
		_add_shapes(w, shapes, float(aus[au]) * scale)


func _add_shapes(w: Dictionary, shapes: Dictionary, scale: float) -> void:
	for shape in shapes:
		_add(w, str(shape), float(shapes[shape]) * scale)


func _add(w: Dictionary, shape: String, value: float) -> void:
	w[shape] = float(w.get(shape, 0.0)) + value
