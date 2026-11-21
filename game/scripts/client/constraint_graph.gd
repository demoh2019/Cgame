extends RefCounted
## Control-Rig style constraint graph: an ordered, data-authored list of
## constraints evaluated on a pose (positions + rotations), built on rig_ik.gd.
##
## Constraint types (dictionary keys, vectors may be Vector3 or [x, y, z]):
##   two_bone       root, mid, tip (bone ids), target, pole, weight
##   aim            bone, forward, target, max_angle (rad), weight
##   fabrik_chain   bones (ids, root first), target, iterations, weight
##   copy_rotation  src, dst, offset ([x,y,z,w] quaternion), weight
##   limit_rotation bone, min_deg, max_deg (euler XYZ degrees)
## Every constraint also takes "enabled" (default true). A target may be a
## position or {"bone": id} to follow another bone's current position.
##
## Credit / licensing: original implementation over rig_ik.gd (itself original).
## The constraint vocabulary mirrors Unreal Control Rig / Blender constraints
## (public documentation only); no third-party code copied.

const RigIK = preload("res://scripts/client/rig_ik.gd")

var constraints: Array[Dictionary] = []
## Filled by evaluate(): [{index, type, applied}] in evaluation order.
var last_log: Array[Dictionary] = []


static func make_pose(positions: PackedVector3Array, rotations: Array[Quaternion] = []) -> Dictionary:
	var rots: Array[Quaternion] = rotations.duplicate()
	while rots.size() < positions.size():
		rots.append(Quaternion.IDENTITY)
	return {"positions": positions.duplicate(), "rotations": rots}


# ---- Authoring ----

func add(c: Dictionary) -> int:
	constraints.append(c)
	return constraints.size() - 1


func remove_at(i: int) -> void:
	if i >= 0 and i < constraints.size():
		constraints.remove_at(i)


## Moves constraint `from` so it ends up at index `to` (changes evaluation order).
func move(from: int, to: int) -> void:
	if from < 0 or from >= constraints.size():
		return
	var c: Dictionary = constraints[from]
	constraints.remove_at(from)
	constraints.insert(clampi(to, 0, constraints.size()), c)


func clear() -> void:
	constraints.clear()


# ---- Data helpers ----

static func _vec(v: Variant, pose: Dictionary) -> Vector3:
	if v is Vector3:
		return v
	if v is Array:
		var a: Array = v
		if a.size() >= 3:
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("bone"):
			var pos: PackedVector3Array = pose["positions"]
			var b: int = int(d["bone"])
			if b >= 0 and b < pos.size():
				return pos[b]
	return Vector3.ZERO


static func _quat(v: Variant) -> Quaternion:
	if v is Quaternion:
		return v
	if v is Array:
		var a: Array = v
		if a.size() >= 4:
			return Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3])).normalized()
	return Quaternion.IDENTITY


static func _valid(pose: Dictionary, bones: Array) -> bool:
	var n: int = (pose["positions"] as PackedVector3Array).size()
	for b in bones:
		if int(b) < 0 or int(b) >= n:
			return false
	return true


# ---- Evaluation ----

## Evaluates all enabled constraints in list order on a copy of `pose`.
func evaluate(pose: Dictionary) -> Dictionary:
	var out: Dictionary = make_pose(pose["positions"], pose.get("rotations", [] as Array[Quaternion]))
	last_log.clear()
	for i in constraints.size():
		var c: Dictionary = constraints[i]
		var type: String = str(c.get("type", ""))
		var applied: bool = false
		if bool(c.get("enabled", true)):
			applied = _apply(out, c, type)
		last_log.append({"index": i, "type": type, "applied": applied})
	return out


func _apply(pose: Dictionary, c: Dictionary, type: String) -> bool:
	var pos: PackedVector3Array = pose["positions"]
	var rots: Array[Quaternion] = pose["rotations"]
	var w: float = clampf(float(c.get("weight", 1.0)), 0.0, 1.0)
	match type:
		"two_bone":
			var ids: Array = [c.get("root", -1), c.get("mid", -1), c.get("tip", -1)]
			if not _valid(pose, ids):
				return false
			var r: int = int(c["root"])
			var m: int = int(c["mid"])
			var t: int = int(c["tip"])
			var target: Vector3 = _vec(c.get("target"), pose)
			var pole: Vector3 = _vec(c.get("pole", pos[m]), pose)
			var res: Dictionary = RigIK.two_bone(pos[r], pos[m], pos[t], target, pole)
			pos[m] = pos[m].lerp(res["mid"], w)
			pos[t] = pos[t].lerp(res["tip"], w)
			pose["positions"] = pos
			return true
		"fabrik_chain":
			var bones: Array = c.get("bones", [])
			if bones.size() < 2 or not _valid(pose, bones):
				return false
			var chain := PackedVector3Array()
			for b in bones:
				chain.append(pos[int(b)])
			var target2: Vector3 = _vec(c.get("target"), pose)
			var solved: PackedVector3Array = RigIK.fabrik_chain(chain, target2, int(c.get("iterations", 16)))
			for k in bones.size():
				var bi: int = int(bones[k])
				pos[bi] = pos[bi].lerp(solved[k], w)
			pose["positions"] = pos
			return true
		"aim":
			if not _valid(pose, [c.get("bone", -1)]):
				return false
			var bone: int = int(c["bone"])
			var fwd: Vector3 = _vec(c.get("forward", Vector3.FORWARD), pose)
			var target3: Vector3 = _vec(c.get("target"), pose)
			var q: Quaternion = RigIK.aim(pos[bone], rots[bone] * fwd, target3, float(c.get("max_angle", PI)))
			rots[bone] = (Quaternion.IDENTITY.slerp(q, w) * rots[bone]).normalized()
			pose["rotations"] = rots
			return true
		"copy_rotation":
			if not _valid(pose, [c.get("src", -1), c.get("dst", -1)]):
				return false
			var src: int = int(c["src"])
			var dst: int = int(c["dst"])
			var goal: Quaternion = rots[src] * _quat(c.get("offset"))
			rots[dst] = rots[dst].slerp(goal, w).normalized()
			pose["rotations"] = rots
			return true
		"limit_rotation":
			if not _valid(pose, [c.get("bone", -1)]):
				return false
			var lb: int = int(c["bone"])
			var lo: Vector3 = _vec(c.get("min_deg", [-180.0, -180.0, -180.0]), pose)
			var hi: Vector3 = _vec(c.get("max_deg", [180.0, 180.0, 180.0]), pose)
			var e: Vector3 = rots[lb].get_euler()
			var deg := Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
			var lim := Vector3(clampf(deg.x, lo.x, hi.x), clampf(deg.y, lo.y, hi.y), clampf(deg.z, lo.z, hi.z))
			var limited: Quaternion = Quaternion.from_euler(Vector3(deg_to_rad(lim.x), deg_to_rad(lim.y), deg_to_rad(lim.z)))
			rots[lb] = rots[lb].slerp(limited, w).normalized()
			pose["rotations"] = rots
			return true
	return false


# ---- JSON ----

static func _to_plain(v: Variant) -> Variant:
	if v is Vector3:
		var vv: Vector3 = v
		return [vv.x, vv.y, vv.z]
	if v is Quaternion:
		var q: Quaternion = v
		return [q.x, q.y, q.z, q.w]
	if v is Array:
		var out: Array = []
		for e in v as Array:
			out.append(_to_plain(e))
		return out
	if v is Dictionary:
		var od := {}
		var src: Dictionary = v
		for k in src:
			od[k] = _to_plain(src[k])
		return od
	return v


func to_json() -> String:
	var list: Array = []
	for c in constraints:
		list.append(_to_plain(c))
	return JSON.stringify({"version": 1, "constraints": list}, "\t")


func from_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	if not d.has("constraints"):
		return false
	constraints.clear()
	for c in d["constraints"] as Array:
		var cd: Dictionary = c
		constraints.append(cd)
	return true
