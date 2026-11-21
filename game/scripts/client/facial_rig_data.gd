extends RefCounted
## Editable facial rig definition: blend shape list, FACS action unit -> blend
## shape mappings, left/right symmetry helpers and JSON save / load.
##
## Credit / licensing: original implementation. Blend shape names follow the
## Apple ARKit convention (naming only) and the AU taxonomy is the public FACS
## research standard (Ekman & Friesen). No third-party code.

const VERSION: int = 1

const ARKIT_SHAPES: Array[String] = [
	"browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight",
	"cheekPuff", "cheekSquintLeft", "cheekSquintRight",
	"eyeBlinkLeft", "eyeBlinkRight", "eyeLookDownLeft", "eyeLookDownRight",
	"eyeLookInLeft", "eyeLookInRight", "eyeLookOutLeft", "eyeLookOutRight",
	"eyeLookUpLeft", "eyeLookUpRight", "eyeSquintLeft", "eyeSquintRight",
	"eyeWideLeft", "eyeWideRight", "jawForward", "jawLeft", "jawOpen", "jawRight",
	"mouthClose", "mouthDimpleLeft", "mouthDimpleRight", "mouthFrownLeft", "mouthFrownRight",
	"mouthFunnel", "mouthLeft", "mouthLowerDownLeft", "mouthLowerDownRight",
	"mouthPressLeft", "mouthPressRight", "mouthPucker", "mouthRight",
	"mouthRollLower", "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper",
	"mouthSmileLeft", "mouthSmileRight", "mouthStretchLeft", "mouthStretchRight",
	"mouthUpperUpLeft", "mouthUpperUpRight", "noseSneerLeft", "noseSneerRight", "tongueOut",
]

var rig_name: String = "face"
var blendshapes: Array[String] = []
## AU key (e.g. "AU12_L") -> {blend shape: weight at AU activation 1}.
var au_map: Dictionary = {}


## Default rig: all ARKit shapes and the mapping used by facial_mocap.gd.
static func default_rig() -> RefCounted:
	var r: RefCounted = load("res://scripts/client/facial_rig_data.gd").new()
	r.blendshapes = ARKIT_SHAPES.duplicate()
	r.au_map = {
		"AU1": {"browInnerUp": 1.0},
		"AU2_L": {"browOuterUpLeft": 1.0},
		"AU2_R": {"browOuterUpRight": 1.0},
		"AU4_L": {"browDownLeft": 1.0},
		"AU4_R": {"browDownRight": 1.0},
		"AU5": {"eyeWideLeft": 1.0, "eyeWideRight": 1.0},
		"AU12_L": {"mouthSmileLeft": 1.0},
		"AU12_R": {"mouthSmileRight": 1.0},
		"AU15_L": {"mouthFrownLeft": 1.0},
		"AU15_R": {"mouthFrownRight": 1.0},
		"AU20": {"mouthStretchLeft": 1.0, "mouthStretchRight": 1.0},
		"AU25": {"mouthLowerDownLeft": 0.4, "mouthLowerDownRight": 0.4},
		"AU26": {"jawOpen": 1.0},
		"AU45_L": {"eyeBlinkLeft": 1.0},
		"AU45_R": {"eyeBlinkRight": 1.0},
	}
	return r


# ---- Editing ----

func add_blendshape(shape: String) -> bool:
	if shape == "" or blendshapes.has(shape):
		return false
	blendshapes.append(shape)
	return true


## Removes a shape and every AU mapping that references it.
func remove_blendshape(shape: String) -> bool:
	var idx: int = blendshapes.find(shape)
	if idx < 0:
		return false
	blendshapes.remove_at(idx)
	for au in au_map.keys():
		var m: Dictionary = au_map[au]
		m.erase(shape)
		if m.is_empty():
			au_map.erase(au)
	return true


func set_mapping(au: String, shape: String, weight: float) -> bool:
	if not blendshapes.has(shape):
		return false
	if not au_map.has(au):
		au_map[au] = {}
	var m: Dictionary = au_map[au]
	if is_zero_approx(weight):
		m.erase(shape)
		if m.is_empty():
			au_map.erase(au)
	else:
		m[shape] = weight
	return true


## Maps AU activations to blend shape weights (summed per shape, clamped 0..1).
func blend(au_values: Dictionary) -> Dictionary:
	var out := {}
	for au in au_values:
		if not au_map.has(au):
			continue
		var a: float = float(au_values[au])
		var m: Dictionary = au_map[au]
		for shape in m:
			out[shape] = float(out.get(shape, 0.0)) + a * float(m[shape])
	for shape in out.keys():
		out[shape] = clampf(float(out[shape]), 0.0, 1.0)
	return out


## Problems found in the rig: mappings that reference unknown shapes.
func validate() -> Array[String]:
	var errs: Array[String] = []
	for au in au_map:
		var m: Dictionary = au_map[au]
		for shape in m:
			if not blendshapes.has(str(shape)):
				errs.append("%s maps to unknown blend shape %s" % [str(au), str(shape)])
	return errs


# ---- Symmetry ----

## "mouthSmileLeft" <-> "mouthSmileRight"; "AU12_L" <-> "AU12_R"; unchanged if sideless.
static func mirror_name(n: String) -> String:
	if n.ends_with("Left"):
		return n.trim_suffix("Left") + "Right"
	if n.ends_with("Right"):
		return n.trim_suffix("Right") + "Left"
	if n.ends_with("_L"):
		return n.trim_suffix("_L") + "_R"
	if n.ends_with("_R"):
		return n.trim_suffix("_R") + "_L"
	return n


## Pairs [left, right] of shapes where both sides exist in the rig.
func symmetry_pairs() -> Array[PackedStringArray]:
	var pairs: Array[PackedStringArray] = []
	for s in blendshapes:
		if s.ends_with("Left") and blendshapes.has(mirror_name(s)):
			pairs.append(PackedStringArray([s, mirror_name(s)]))
	return pairs


## Shapes with a side suffix whose mirror is missing from the rig.
func asymmetric_shapes() -> Array[String]:
	var out: Array[String] = []
	for s in blendshapes:
		if (s.ends_with("Left") or s.ends_with("Right")) and not blendshapes.has(mirror_name(s)):
			out.append(s)
	return out


## Rebuilds the right-side AU mappings from the left side (or the reverse).
## Returns the number of mappings written.
func symmetrize(from_left: bool = true) -> int:
	var src_suffix: String = "_L" if from_left else "_R"
	var written: int = 0
	for au in au_map.keys():
		var key: String = str(au)
		if not key.ends_with(src_suffix):
			continue
		var m: Dictionary = au_map[au]
		var mirrored := {}
		for shape in m:
			mirrored[mirror_name(str(shape))] = m[shape]
		au_map[mirror_name(key)] = mirrored
		written += 1
	return written


# ---- Persistence ----

func to_dict() -> Dictionary:
	var shapes: Array = []
	for s in blendshapes:
		shapes.append(s)
	return {"version": VERSION, "name": rig_name, "blendshapes": shapes, "au_map": au_map.duplicate(true)}


func from_dict(d: Dictionary) -> bool:
	if not d.has("blendshapes") or not d.has("au_map"):
		return false
	rig_name = str(d.get("name", "face"))
	blendshapes.clear()
	for s in d["blendshapes"] as Array:
		blendshapes.append(str(s))
	au_map = {}
	var src: Dictionary = d["au_map"]
	for au in src:
		var m: Dictionary = src[au]
		var nm := {}
		for shape in m:
			nm[str(shape)] = float(m[shape])
		au_map[str(au)] = nm
	return true


func save_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true


func load_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	return from_dict(d)
