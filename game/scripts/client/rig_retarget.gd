extends RefCounted
## Runtime IK retargeting between humanoid skeletons of different proportions: bone-name
## mapping (Mixamo / Unreal mannequin / Quaternius / generic), local-rotation transfer with
## root translation scaled by the leg-length ratio, and two-bone foot IK to keep contact.
##
## Credit / licensing: original implementation. The approach (name-map + rotation transfer +
## hips scaled by leg-length ratio + foot IK correction) follows the general technique used by
## engine retargeters (e.g. Unreal IK Retargeter, Unity Humanoid/Mecanim avatars) as described in
## their public documentation; no source code from those or any other project was copied or ported.
## No Apache-2.0 / MIT / BSD code is included.
##
## Rig dictionary: {"names": PackedStringArray, "parents": PackedInt32Array (parents precede
## children), "rest": PackedVector3Array (global rest joint positions),
## "rest_rot": Array[Quaternion] (optional local rest rotations, default identity)}.
## Pose dictionary: {"rot": Array[Quaternion] local rotations relative to rest, "hips": Vector3
## global hips position}.

const RigIK = preload("res://scripts/client/rig_ik.gd")

const _BASE_ALIASES := {
	"hips": "hips", "pelvis": "hips", "hip": "hips",
	"spine": "spine", "spine01": "spine", "abdomen": "spine",
	"spine1": "spine1", "spine02": "spine1", "torso": "spine1",
	"spine2": "spine2", "spine03": "spine2", "chest": "spine2",
	"neck": "neck", "neck01": "neck", "neck1": "neck",
	"head": "head",
	"shoulder": "shoulder", "clavicle": "shoulder",
	"upperarm": "upperarm", "arm": "upperarm",
	"forearm": "lowerarm", "lowerarm": "lowerarm",
	"hand": "hand", "fist": "hand",
	"upleg": "upperleg", "thigh": "upperleg", "upperleg": "upperleg",
	"leg": "lowerleg", "calf": "lowerleg", "lowerleg": "lowerleg", "shin": "lowerleg",
	"foot": "foot",
	"toebase": "toe", "toe": "toe", "toes": "toe", "ball": "toe",
}


## Canonical key for a bone name, e.g. "mixamorig:LeftUpLeg" -> "upperleg|l". Empty if unknown.
static func canonical(bone_name: String, aliases: Dictionary = {}) -> String:
	if aliases.has(bone_name):
		return str(aliases[bone_name])
	var s := bone_name
	for sep in [":", "|"]:
		var k := s.rfind(sep)
		if k >= 0:
			s = s.substr(k + 1)
	s = s.to_lower().replace(".", "_").replace(" ", "_").replace("-", "_")
	for prefix in ["mixamorig", "bip001", "bip01", "def", "j_bip"]:
		if s.begins_with(prefix):
			s = s.substr(prefix.length()).trim_prefix("_")
			break
	var side := ""
	if s.begins_with("left"):
		side = "l"
		s = s.substr(4).trim_prefix("_")
	elif s.begins_with("right"):
		side = "r"
		s = s.substr(5).trim_prefix("_")
	elif s.begins_with("l_"):
		side = "l"
		s = s.substr(2)
	elif s.begins_with("r_"):
		side = "r"
		s = s.substr(2)
	else:
		for suffix in ["_left", "_right", "_l", "_r"]:
			if s.ends_with(suffix):
				side = "l" if suffix in ["_left", "_l"] else "r"
				s = s.substr(0, s.length() - suffix.length())
				break
	s = s.replace("_", "")
	if aliases.has(s):
		return str(aliases[s]) + ("|" + side if side != "" else "")
	if not _BASE_ALIASES.has(s):
		return ""
	var base: String = _BASE_ALIASES[s]
	return base + ("|" + side if side != "" else "")


## Maps source bone index -> target bone index by canonical humanoid name (with identical raw
## names as a fallback). `aliases` may map raw names (or normalised lower-case base names) to a
## canonical key such as "hand|l" for custom rigs.
static func build_map(source_names: PackedStringArray, target_names: PackedStringArray, aliases: Dictionary = {}) -> Dictionary:
	var target_by_key := {}
	var target_by_raw := {}
	for j in target_names.size():
		target_by_raw[target_names[j]] = j
		var key := canonical(target_names[j], aliases)
		if key != "" and not target_by_key.has(key):
			target_by_key[key] = j
	var map := {}
	var used := {}
	for i in source_names.size():
		var key := canonical(source_names[i], aliases)
		var j := -1
		if key != "" and target_by_key.has(key):
			j = target_by_key[key]
		elif target_by_raw.has(source_names[i]):
			j = target_by_raw[source_names[i]]
		if j >= 0 and not used.has(j):
			map[i] = j
			used[j] = true
	return map


## Index of the bone with a canonical key ("hips", "foot|l", ...), or -1.
static func find_bone(names: PackedStringArray, key: String, aliases: Dictionary = {}) -> int:
	for i in names.size():
		if canonical(names[i], aliases) == key:
			return i
	return -1


static func _local_rest(rig: Dictionary, i: int) -> Quaternion:
	var rr: Array = rig.get("rest_rot", [])
	if i < rr.size():
		var q: Quaternion = rr[i]
		return q
	return Quaternion.IDENTITY


## Forward kinematics. Returns {"pos": PackedVector3Array, "rot": Array[Quaternion] (global)}.
## `hips_bone` is placed at `hips`; everything else derives from rest offsets and rotations.
static func fk(rig: Dictionary, rots: Array, hips_bone: int, hips: Vector3) -> Dictionary:
	var parents: PackedInt32Array = rig["parents"]
	var rest: PackedVector3Array = rig["rest"]
	var n := parents.size()
	var pos := PackedVector3Array()
	pos.resize(n)
	var glob: Array = []
	glob.resize(n)
	var rest_glob: Array = []
	rest_glob.resize(n)
	for i in n:
		var p := parents[i]
		var lr := _local_rest(rig, i)
		var pose_q := Quaternion.IDENTITY
		if i < rots.size():
			var rq: Quaternion = rots[i]
			pose_q = rq
		if p < 0:
			rest_glob[i] = lr
			glob[i] = lr * pose_q
			pos[i] = rest[i]
		else:
			var rgp: Quaternion = rest_glob[p]
			var gp: Quaternion = glob[p]
			rest_glob[i] = rgp * lr
			glob[i] = gp * lr * pose_q
			pos[i] = pos[p] + gp * (rgp.inverse() * (rest[i] - rest[p]))
		if i == hips_bone:
			pos[i] = hips
	return {"pos": pos, "rot": glob}


static func _leg_length(rig: Dictionary, hips_idx: int, foot_idx: int) -> float:
	var rest: PackedVector3Array = rig["rest"]
	if hips_idx < 0 or foot_idx < 0:
		return 0.0
	return rest[hips_idx].distance_to(rest[foot_idx])


## Transfers local rotations through `map` (source idx -> target idx) and scales the hips
## position by the leg-length ratio (horizontal travel scaled, vertical offset from the rest
## height scaled). Unmapped target bones stay at rest. Returns {"rot", "hips", "ratio"}.
static func retarget_pose(source_rest: Dictionary, source_pose: Dictionary, target_rest: Dictionary, map: Dictionary) -> Dictionary:
	var s_names: PackedStringArray = source_rest["names"]
	var t_names: PackedStringArray = target_rest["names"]
	var s_rest: PackedVector3Array = source_rest["rest"]
	var t_rest: PackedVector3Array = target_rest["rest"]
	var src_rot: Array = source_pose["rot"]
	var rots: Array = []
	for _j in t_names.size():
		rots.append(Quaternion.IDENTITY)
	for k in map:
		var si: int = k
		var ti: int = map[k]
		if si < src_rot.size() and ti < rots.size():
			rots[ti] = src_rot[si]
	var s_hips := find_bone(s_names, "hips")
	var t_hips := find_bone(t_names, "hips")
	var ratio := 1.0
	var s_leg := _leg_length(source_rest, s_hips, find_bone(s_names, "foot|l"))
	var t_leg := _leg_length(target_rest, t_hips, find_bone(t_names, "foot|l"))
	if s_leg > 0.0001 and t_leg > 0.0001:
		ratio = t_leg / s_leg
	var hips := Vector3.ZERO
	if t_hips >= 0:
		hips = t_rest[t_hips]
	if s_hips >= 0 and t_hips >= 0:
		var sh: Vector3 = source_pose.get("hips", s_rest[s_hips])
		var d := sh - s_rest[s_hips]
		hips = t_rest[t_hips] + d * ratio
	return {"rot": rots, "hips": hips, "ratio": ratio}


## Keeps foot contact: for each {target foot bone index: world position} two-bone IK is run on
## the leg (upper leg, lower leg, foot) with the current knee as the pole vector, and the local
## rotations of both leg bones are rewritten (foot keeps its global orientation). Returns
## {"rot", "hips", "pos" (global joint positions), "error" (max foot miss)}.
static func ik_correct_feet(target_rig: Dictionary, pose: Dictionary, foot_targets: Dictionary) -> Dictionary:
	var parents: PackedInt32Array = target_rig["parents"]
	var names: PackedStringArray = target_rig["names"]
	var rots_in: Array = pose["rot"]
	var rots := rots_in.duplicate()
	var hips: Vector3 = pose["hips"]
	var hips_bone := find_bone(names, "hips")
	var state := fk(target_rig, rots, hips_bone, hips)
	var worst := 0.0
	for k in foot_targets:
		var foot: int = k
		var goal: Vector3 = foot_targets[k]
		var lower := parents[foot]
		if lower < 0:
			continue
		var upper := parents[lower]
		if upper < 0:
			continue
		var pos: PackedVector3Array = state["pos"]
		var glob: Array = state["rot"]
		var res := RigIK.two_bone(pos[upper], pos[lower], pos[foot], goal, pos[lower])
		var new_mid: Vector3 = res["mid"]
		var new_tip: Vector3 = res["tip"]
		# Swing upper leg, then lower leg; keep the foot's global rotation.
		var gu: Quaternion = glob[upper]
		var gl: Quaternion = glob[lower]
		var gf: Quaternion = glob[foot]
		var du := RigIK.aim(Vector3.ZERO, pos[lower] - pos[upper], new_mid - pos[upper])
		var new_gu := du * gu
		var dl := RigIK.aim(Vector3.ZERO, du * (pos[foot] - pos[lower]), new_tip - new_mid)
		var new_gl := dl * du * gl
		rots[upper] = _local_pose(target_rig, glob, parents, upper, new_gu, rots)
		rots[lower] = _local_pose_from(target_rig, lower, new_gu, new_gl)
		rots[foot] = _local_pose_from(target_rig, foot, new_gl, gf)
		state = fk(target_rig, rots, hips_bone, hips)
	for k in foot_targets:
		var f2: int = k
		var p2: PackedVector3Array = state["pos"]
		var goal2: Vector3 = foot_targets[k]
		worst = maxf(worst, p2[f2].distance_to(goal2))
	return {"rot": rots, "hips": hips, "pos": state["pos"], "error": worst}


static func _local_pose(rig: Dictionary, glob: Array, parents: PackedInt32Array, i: int, new_global: Quaternion, _rots: Array) -> Quaternion:
	var parent_q := Quaternion.IDENTITY
	if parents[i] >= 0:
		var gp: Quaternion = glob[parents[i]]
		parent_q = gp
	return _local_pose_from(rig, i, parent_q, new_global)


## Local pose rotation (relative to rest) giving global rotation `new_global` under a parent
## with global rotation `parent_global`.
static func _local_pose_from(rig: Dictionary, i: int, parent_global: Quaternion, new_global: Quaternion) -> Quaternion:
	return (_local_rest(rig, i)).inverse() * parent_global.inverse() * new_global
